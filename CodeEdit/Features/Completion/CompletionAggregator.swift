//
//  CompletionAggregator.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import AppKit
import CodeEditSourceEditor
import CodeEditTextView

/// Merges completions from several ``CompletionProvider``s (language server, snippets/keywords,
/// and an opt-in AI provider) into one ranked, badged list for the source editor's suggestion
/// window.
///
/// Installed per document by ``CodeFileView`` in place of a single ``LSPCompletionProvider``. Each
/// request first recognizes the user's ``CompletionIntent`` at the cursor (member access, a type, a
/// case label, a new declaration's name, …). The intent decides whether a typing-triggered request
/// opens the window at all, which snippets and keywords are offered, and how candidates are ranked.
///
/// Each provider is raced against its own deadline; a provider that answers late (in practice, the
/// AI provider) has its result merged in on the next cursor move rather than blocking the window.
@MainActor
final class CompletionAggregator: CodeSuggestionDelegate {
    /// Characters that are considered part of a symbol when finding the typed prefix.
    private static let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$#"))

    private weak var document: CodeFileDocument?
    private let treeSitterClient: TreeSitterClient
    private let frequencyStore: CompletionFrequencyStoring

    private let lspProvider: LSPCompletionProvider
    private let snippetProvider: TreeSitterSnippetProvider
    private var aiProvider: (any AICompletionProvider)?

    /// All providers, in fan-out order.
    private var providers: [any CompletionProvider] {
        var all: [any CompletionProvider] = [lspProvider, snippetProvider]
        if let aiProvider { all.append(aiProvider) }
        return all
    }

    /// The provider that produced each candidate in the current session, keyed by candidate id.
    private var candidateOwners: [String: any CompletionProvider] = [:]
    /// The raw (pre-filter) candidate pool gathered for the current request, used to re-run the
    /// pipeline synchronously as the user keeps typing.
    private var rawCandidates: [CompletionCandidate] = []
    /// The context the last request was made with. Only `prefix`/`prefixRange` change as the user
    /// types; everything else stays pinned to the original request.
    private var requestContext: CompletionContext?
    /// The document offset the cursor was at when the last completion request was made.
    private var requestOffset: Int?
    /// Results that arrived after the window opened, kept until the next cursor move so they can be
    /// merged in without blocking the window. Cleared when merged or when a new request starts.
    private var lateResults: [(provider: any CompletionProvider, candidates: [CompletionCandidate])] = []
    /// Incremented on every request and on close so results from a superseded request are dropped.
    private var requestGeneration = 0

    init(
        document: CodeFileDocument,
        treeSitterClient: TreeSitterClient,
        frequencyStore: CompletionFrequencyStoring = CompletionFrequencyStore.shared
    ) {
        self.document = document
        self.treeSitterClient = treeSitterClient
        self.frequencyStore = frequencyStore
        self.lspProvider = LSPCompletionProvider(document: document)
        self.snippetProvider = TreeSitterSnippetProvider()
        self.aiProvider = ClaudeCompletionProvider()
    }

    // MARK: - CodeSuggestionDelegate

    func completionTriggerCharacters() -> Set<String> {
        providers.reduce(into: Set<String>()) { $0.formUnion($1.triggerCharacters()) }
    }

    func completionSuggestionsRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])? {
        await completionSuggestionsRequested(textView: textView, cursorPosition: cursorPosition, trigger: .explicit)
    }

    func completionSuggestionsRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition,
        trigger: CodeSuggestionTrigger
    ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])? {
        guard let resolved = textView.resolveCursorPosition(cursorPosition) else { return nil }
        let location = resolved.range.location
        let string = textView.textView.textStorage.string as NSString
        let context = buildContext(string: string, location: location, isExplicit: trigger == .explicit)
        // Typing in a comment, a string, a number, or a new declaration's name: stay out of the way
        // without asking any provider.
        guard context.isExplicit || CompletionIntentPolicy.allowsAutomaticCompletion(for: context.intent) else {
            return nil
        }

        requestContext = context
        requestOffset = location
        lateResults = []
        candidateOwners = [:]
        requestGeneration += 1

        let gathered = await gatherCandidates(context: context, textView: textView, generation: requestGeneration)
        guard !Task.isCancelled else { return nil }

        rawCandidates = gathered
        let ranked = rank(gathered, prefix: context.prefix, context: context)
        let entries = CompletionPresenter.present(ranked)
        guard !entries.isEmpty else { return nil }
        return (cursorPosition, entries)
    }

    func completionOnCursorMove(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) -> [CodeSuggestionEntry]? {
        guard var context = requestContext,
              let requestOffset,
              let resolved = textView.resolveCursorPosition(cursorPosition) else {
            return nil
        }
        let location = resolved.range.location
        let string = textView.textView.textStorage.string as NSString
        guard location >= requestOffset, location <= string.length else { return nil }

        if location > requestOffset {
            let wordRange = wordRange(in: string, at: location)
            // A non-word character typed since the request (the second `:` of `::`, `.`, `->`, a
            // space) starts a new word at a different completion site. The cached candidates don't
            // apply there, so close and let the trigger re-request.
            guard wordRange.location == context.prefixRange.location else { return nil }
            context.prefix = string.substring(with: wordRange)
            context.prefixRange = wordRange
        }

        for late in lateResults {
            for candidate in late.candidates { candidateOwners[candidate.id] = late.provider }
            rawCandidates.append(contentsOf: late.candidates)
        }
        lateResults = []

        requestContext = context
        let ranked = rank(rawCandidates, prefix: context.prefix, context: context)
        let entries = CompletionPresenter.present(ranked)
        return entries.isEmpty ? nil : entries
    }

    func completionWindowApplyCompletion(
        item: CodeSuggestionEntry,
        textView: TextViewController,
        cursorPosition: CursorPosition?
    ) {
        guard let entry = item as? AggregatedCompletionEntry else { return }
        let candidate = entry.candidate
        candidateOwners[candidate.id]?.apply(candidate, textView: textView, cursorPosition: cursorPosition)
        frequencyStore.recordAcceptance(label: candidate.label, languageId: requestContext?.languageId ?? "")
    }

    func completionWindowResolve(item: CodeSuggestionEntry) async -> CodeSuggestionEntry? {
        guard let entry = item as? AggregatedCompletionEntry,
              let provider = candidateOwners[entry.candidate.id],
              let resolved = await provider.resolve(entry.candidate) else {
            return nil
        }
        if let index = rawCandidates.firstIndex(where: { $0.id == entry.candidate.id }) {
            rawCandidates[index] = resolved
        }
        return AggregatedCompletionEntry(candidate: resolved)
    }

    func completionWindowDidClose() {
        rawCandidates = []
        candidateOwners = [:]
        requestContext = nil
        requestOffset = nil
        lateResults = []
        requestGeneration += 1
    }

    // MARK: - Context

    private func buildContext(string: NSString, location: Int, isExplicit: Bool) -> CompletionContext {
        let prefixRange = wordRange(in: string, at: location)
        let prefix = string.substring(with: prefixRange)
        let lineStart = lineStart(in: string, before: location)
        let lineTextBeforeCursor = string.substring(with: NSRange(location: lineStart, length: location - lineStart))
        let languageId = document?.getLanguage().id.rawValue ?? ""
        let recognizer = CompletionIntentRecognizer(treeSitterClient: treeSitterClient)
        let intent = recognizer.recognize(
            at: location,
            prefix: prefix,
            lineTextBeforeCursor: lineTextBeforeCursor,
            languageId: languageId
        )

        return CompletionContext(
            prefix: prefix,
            prefixRange: prefixRange,
            triggerCharacter: location > 0 ? string.substring(with: NSRange(location: location - 1, length: 1)) : nil,
            intent: intent,
            languageId: languageId,
            documentText: string as String,
            cursorOffset: location,
            isExplicit: isExplicit
        )
    }

    private func wordRange(in string: NSString, at location: Int) -> NSRange {
        var start = location
        while start > 0,
              let scalar = Unicode.Scalar(string.character(at: start - 1)),
              Self.wordCharacters.contains(scalar) {
            start -= 1
        }
        return NSRange(location: start, length: location - start)
    }

    private func lineStart(in string: NSString, before location: Int) -> Int {
        var start = location
        while start > 0 && string.character(at: start - 1) != 0x0A {
            start -= 1
        }
        return start
    }

    private func rank(
        _ candidates: [CompletionCandidate],
        prefix: String,
        context: CompletionContext
    ) -> [CompletionCandidate] {
        let deduped = CompletionDeduplicator.deduplicate(candidates)
        let frequencies = frequencyStore.frequencies(for: context.languageId)
        return CompletionRanker.rank(
            deduped,
            prefix: prefix,
            intent: context.intent,
            isExplicit: context.isExplicit,
            frequencies: frequencies
        )
    }

    // MARK: - Fan-out with per-provider deadlines

    /// One provider's in-flight request for the current completion session.
    @MainActor
    private final class ProviderRun {
        let provider: any CompletionProvider
        var result: [CompletionCandidate]?
        /// Set once the window has opened without this run; receives the result when it arrives.
        var onLateResult: (([CompletionCandidate]) -> Void)?
        var task: Task<Void, Never>?

        init(provider: any CompletionProvider) {
            self.provider = provider
        }
    }

    /// Queries every provider concurrently.
    ///
    /// Providers with a zero `deadline` (language server, snippets) are awaited in full, as the
    /// language server was before the aggregator existed. Providers with a deadline (AI) never
    /// hold the window open once the others have answered: whatever they have returned by then is
    /// included, and a later answer is kept in `lateResults` for the next cursor move. When the
    /// blocking providers return nothing, a deadline provider is waited on for up to its deadline so
    /// the window can still open with its items alone.
    private func gatherCandidates(
        context: CompletionContext,
        textView: TextViewController,
        generation: Int
    ) async -> [CompletionCandidate] {
        let runs = providers.map { ProviderRun(provider: $0) }
        for run in runs {
            run.task = Task { @MainActor in
                let result = await run.provider.candidates(for: context, textView: textView)
                run.result = result
                run.onLateResult?(result)
            }
        }
        let tasks = runs.compactMap(\.task)

        return await withTaskCancellationHandler {
            await self.collect(runs, generation: generation)
        } onCancel: {
            tasks.forEach { $0.cancel() }
        }
    }

    /// Awaits zero-deadline runs in full, then takes whatever the deadline runs have returned.
    private func collect(_ runs: [ProviderRun], generation: Int) async -> [CompletionCandidate] {
        var gathered: [CompletionCandidate] = []
        func take(_ run: ProviderRun) {
            guard let result = run.result else { return }
            for candidate in result { candidateOwners[candidate.id] = run.provider }
            gathered.append(contentsOf: result)
        }

        for run in runs where run.provider.deadline == .zero {
            await run.task?.value
            take(run)
        }
        for run in runs where run.provider.deadline > .zero {
            if run.result == nil, gathered.isEmpty, let task = run.task {
                await Self.wait(for: task, upTo: run.provider.deadline)
            }
            if run.result != nil {
                take(run)
            } else {
                let provider = run.provider
                run.onLateResult = { [weak self] result in
                    guard let self, self.requestGeneration == generation, !result.isEmpty else { return }
                    self.lateResults.append((provider, result))
                }
            }
        }
        return gathered
    }

    /// Waits for `task` to finish or for `duration` to elapse, whichever comes first.
    private static func wait(for task: Task<Void, Never>, upTo duration: Duration) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await task.value }
            group.addTask { try? await Task.sleep(for: duration) }
            await group.next()
            group.cancelAll()
        }
    }
}
