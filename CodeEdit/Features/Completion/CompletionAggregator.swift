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
    var providers: [any CompletionProvider] {
        var all: [any CompletionProvider] = [lspProvider, snippetProvider]
        if let aiProvider { all.append(aiProvider) }
        return all
    }

    /// The provider that produced each candidate in the current session, keyed by candidate id.
    var candidateOwners: [String: any CompletionProvider] = [:]
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
    var lateResults: [(provider: any CompletionProvider, candidates: [CompletionCandidate])] = []
    /// Incremented on every request and on close so results from a superseded request are dropped.
    var requestGeneration = 0

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
        let result = await completionSuggestionsResult(
            textView: textView,
            cursorPosition: cursorPosition,
            trigger: trigger
        )
        return result.map { ($0.windowPosition, $0.items) }
    }

    func completionSuggestionsResult(
        textView: TextViewController,
        cursorPosition: CursorPosition,
        trigger: CodeSuggestionTrigger
    ) async -> CodeSuggestionResult? {
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
        let entries = CompletionPresenter.present(ranked.items)
        guard !entries.isEmpty else { return nil }
        return CodeSuggestionResult(
            windowPosition: cursorPosition,
            items: entries,
            preselectedIndex: ranked.preselectedIndex
        )
    }

    func completionOnCursorMove(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) -> [CodeSuggestionEntry]? {
        completionSuggestionsUpdated(textView: textView, cursorPosition: cursorPosition)?.items
    }

    func completionSuggestionsUpdated(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) -> CodeSuggestionUpdate? {
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
        let entries = CompletionPresenter.present(ranked.items)
        return entries.isEmpty ? nil : CodeSuggestionUpdate(items: entries, preselectedIndex: ranked.preselectedIndex)
    }

    func completionWindowApplyCompletion(
        item: CodeSuggestionEntry,
        textView: TextViewController,
        cursorPosition: CursorPosition?
    ) {
        completionWindowApplyCompletion(
            item: item,
            textView: textView,
            cursorPosition: cursorPosition,
            commitCharacter: nil
        )
    }

    func completionWindowApplyCompletion(
        item: CodeSuggestionEntry,
        textView: TextViewController,
        cursorPosition: CursorPosition?,
        commitCharacter: Character?
    ) {
        guard let entry = item as? AggregatedCompletionEntry else { return }
        let candidate = entry.candidate
        candidateOwners[candidate.id]?.apply(
            candidate,
            textView: textView,
            cursorPosition: cursorPosition,
            commitCharacter: commitCharacter
        )
        frequencyStore.recordAcceptance(label: candidate.label, languageId: requestContext?.languageId ?? "")
    }

    func completionCommitCharacters(for item: CodeSuggestionEntry) -> Set<Character> {
        guard Settings[\.textEditing].completion.commitCharactersEnabled,
              let entry = item as? AggregatedCompletionEntry,
              let context = requestContext else {
            return []
        }
        return CommitCharacters.characters(
            for: entry.candidate,
            languageId: context.languageId,
            prefix: context.prefix,
            pool: rawCandidates
        )
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
    ) -> RankedCompletions {
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
}
