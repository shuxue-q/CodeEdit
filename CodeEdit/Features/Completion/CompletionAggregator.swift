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
    static let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$#"))

    weak var document: CodeFileDocument?
    let treeSitterClient: TreeSitterClient
    let frequencyStore: CompletionFrequencyStoring
    /// Where popup, acceptance and latency measurements go.
    let metrics: any CompletionMetricsRecording

    private let lspProvider: LSPCompletionProvider
    private let snippetProvider: TreeSitterSnippetProvider
    let wordProvider: DocumentWordProvider
    private let postfixProvider: PostfixCompletionProvider
    /// The second stage of chain requests; not part of the regular fan-out.
    let chainProvider: ChainCompletionProvider
    /// Works out the type the slot at the cursor expects. Replaceable so tests need no language server.
    let expectedTypeSource: (CompletionContext, TextViewController) async -> TypeText?
    /// Works out the type of the object whose members are being completed.
    let receiverTypeSource: (CompletionContext, TextViewController) async -> String?
    private var aiProvider: (any AICompletionProvider)?
    /// Extra providers queried alongside the built-in ones. Empty in the app; tests inject fakes here.
    private let additionalProviders: [any CompletionProvider]

    /// All providers, in fan-out order.
    var providers: [any CompletionProvider] {
        var all: [any CompletionProvider] = [lspProvider, snippetProvider, postfixProvider, wordProvider]
        if let aiProvider { all.append(aiProvider) }
        return all + additionalProviders
    }

    /// The provider that produced each candidate in the current session, keyed by candidate id.
    var candidateOwners: [String: any CompletionProvider] = [:]
    /// The raw (pre-filter) candidate pool gathered for the current request, used to re-run the
    /// pipeline synchronously as the user keeps typing.
    var rawCandidates: [CompletionCandidate] = []
    /// The context the last request was made with. Only `prefix`/`prefixRange` change as the user
    /// types; everything else stays pinned to the original request.
    private var requestContext: CompletionContext?
    /// The document offset the cursor was at when the last completion request was made.
    private var requestOffset: Int?
    /// Results that arrived after the window opened, kept until the next cursor move so they can be
    /// merged in without blocking the window. Cleared when merged or when a new request starts.
    var lateResults: [(provider: any CompletionProvider, candidates: [CompletionCandidate])] = []
    /// Whether the current request already asked ``DocumentWordProvider`` for words. It does not for a
    /// one-character prefix; the words are then merged in once the prefix is long enough.
    var wordCandidatesGathered = false
    /// The provider requests of the current session, cancelled when a newer request or a close supersedes them.
    var inFlightProviderTasks: [Task<Void, Never>] = []
    /// The candidate ids in the order the window last showed them, to find an accepted item's rank.
    private var presentedIDs: [String] = []
    /// How many times the list was refreshed since the window opened.
    private var refreshesSincePopup = 0
    /// What the frequency store knows for the current request's language and intent.
    var statistics = CompletionStatistics()
    /// Incremented on every request and on close so results from a superseded request are dropped.
    var requestGeneration = 0

    init(
        document: CodeFileDocument,
        treeSitterClient: TreeSitterClient,
        frequencyStore: CompletionFrequencyStoring = CompletionFrequencyStore.shared,
        metrics: any CompletionMetricsRecording = CompletionMetricsStore.shared,
        additionalProviders: [any CompletionProvider] = [],
        expectedTypeSource: ((CompletionContext, TextViewController) async -> TypeText?)? = nil,
        receiverTypeSource: ((CompletionContext, TextViewController) async -> String?)? = nil,
        chainServerFactory: (() -> ChainScratchServer?)? = nil
    ) {
        self.document = document
        self.treeSitterClient = treeSitterClient
        self.frequencyStore = frequencyStore
        self.metrics = metrics
        self.additionalProviders = additionalProviders
        let lspProvider = LSPCompletionProvider(document: document)
        self.lspProvider = lspProvider
        self.snippetProvider = TreeSitterSnippetProvider()
        self.wordProvider = DocumentWordProvider()
        self.postfixProvider = PostfixCompletionProvider(treeSitterClient: treeSitterClient)
        self.aiProvider = CloudAICompletionProvider()
        self.chainProvider = ChainCompletionProvider(
            makeServer: chainServerFactory ?? { [weak lspProvider, weak document] in
                guard let lspProvider, let document else { return nil }
                return lspProvider.makeChainScratchServer(for: document)
            }
        )
        let sources = Self.semanticSources(
            document: document,
            treeSitterClient: treeSitterClient,
            lspProvider: lspProvider
        )
        self.expectedTypeSource = expectedTypeSource ?? sources.expectedType
        self.receiverTypeSource = receiverTypeSource ?? sources.receiverType
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
        var context = buildContext(string: string, location: location, isExplicit: trigger != .typing)
        context.isChain = trigger == .chain
        // Typing in a comment, a string, a number, or a new declaration's name: stay out of the way
        // without asking any provider.
        guard context.isExplicit || CompletionIntentPolicy.allowsAutomaticCompletion(for: context.intent) else {
            return nil
        }

        inFlightProviderTasks.forEach { $0.cancel() }
        inFlightProviderTasks = []
        requestContext = context
        requestOffset = location
        lateResults = []
        candidateOwners = [:]
        requestGeneration += 1

        let requestStart = ContinuousClock.now
        let semantics = startSemanticTasks(context: context, textView: textView)
        let gathered = await gatherCandidates(context: context, textView: textView, generation: requestGeneration)
        guard !Task.isCancelled else {
            semantics.cancel()
            return nil
        }
        let pool = await finishSemantics(semantics, context: &context, gathered: gathered, since: requestStart)
        requestContext = context

        rawCandidates = pool
        wordCandidatesGathered = context.isExplicit || context.prefix.count >= DocumentWordProvider.minimumPrefixLength
        let ranked = rank(pool, prefix: context.prefix, context: context)
        let entries = CompletionPresenter.present(ranked.items)
        guard !entries.isEmpty else { return nil }
        metrics.recordPopup()
        presentedIDs = ranked.items.map(\.id)
        refreshesSincePopup = 0
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

        mergeWordCandidatesIfNeeded(context: context)
        for late in lateResults {
            for candidate in late.candidates { candidateOwners[candidate.id] = late.provider }
            rawCandidates.append(contentsOf: late.candidates)
        }
        lateResults = []

        requestContext = context
        let ranked = rank(rawCandidates, prefix: context.prefix, context: context)
        let entries = CompletionPresenter.present(ranked.items)
        guard !entries.isEmpty else { return nil }
        presentedIDs = ranked.items.map(\.id)
        refreshesSincePopup += 1
        return CodeSuggestionUpdate(items: entries, preselectedIndex: ranked.preselectedIndex)
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
        metrics.recordAcceptance(
            rank: presentedIDs.firstIndex(of: candidate.id) ?? 0,
            keystrokes: refreshesSincePopup
        )
        frequencyStore.recordAcceptance(
            label: candidate.label,
            languageId: requestContext?.languageId ?? "",
            intent: requestContext?.intent ?? .unknown,
            receiverType: requestContext?.receiverType,
            at: Date()
        )
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
        inFlightProviderTasks.forEach { $0.cancel() }
        inFlightProviderTasks = []
        presentedIDs = []
        rawCandidates = []
        candidateOwners = [:]
        requestContext = nil
        requestOffset = nil
        lateResults = []
        requestGeneration += 1
    }
}
