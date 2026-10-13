//
//  CompletionAggregator+ServerRefresh.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/13/26.
//

import AppKit
import CodeEditSourceEditor

// MARK: - Incomplete server lists

extension CompletionAggregator {
    /// What the aggregator knows about the language server's list in the current session.
    struct ServerListState {
        /// Whether the server's candidates in the pool come from a list it marked incomplete. Stays set
        /// while a re-request is in flight.
        var isIncomplete = false
        /// The prefix the server's current candidates were requested with.
        var requestPrefix: String?
        /// The re-request in flight, cancelled by a newer one or a close.
        var refreshTask: Task<Void, Never>?
        /// Set while the window re-reads its rows after a re-request, which is not a keystroke.
        var isApplyingRefresh = false

        /// Cancels the re-request in flight and forgets the list.
        mutating func reset() {
            refreshTask?.cancel()
            self = ServerListState()
        }
    }

    /// Records what the first list holds from the language server: the prefix it was asked with, and
    /// whether the server marked it incomplete. A server that answered after the window opened is
    /// recorded when its late result is merged.
    func noteServerList(requestedWith prefix: String) {
        serverList.requestPrefix = prefix
        let serverAnswered = candidateOwners.values.contains { $0 === lspProvider }
        serverList.isIncomplete = serverAnswered && lspProvider.lastListIsIncomplete
    }

    /// Asks the language server again when its list was incomplete and the prefix has changed since it
    /// was asked, instead of only filtering what it sent.
    ///
    /// Only for languages in ``LSPCompletionProvider/incompleteListLanguageIds``. The Dart analysis
    /// server caps its list (see `LanguageServerConfiguration`) and marks a capped list incomplete, so a
    /// symbol that ranked below the cap for `P` can be the best match for `Pad`. A complete list is only
    /// good for prefixes that extend the one it was asked with, so deleting back past that prefix asks
    /// again too. The window keeps showing the filtered list until the new answer replaces the server's
    /// candidates and the rows are re-read; a newer keystroke cancels the re-request in flight. An empty
    /// answer (an error, or nothing matching) keeps the previous list.
    func refreshServerListIfNeeded(context: CompletionContext, location: Int, textView: TextViewController) {
        guard !serverList.isApplyingRefresh,
              LSPCompletionProvider.incompleteListLanguageIds.contains(context.languageId),
              let requested = serverList.requestPrefix, requested != context.prefix,
              serverList.isIncomplete || !context.prefix.hasPrefix(requested) else {
            return
        }
        serverList.requestPrefix = context.prefix
        serverList.refreshTask?.cancel()
        var refreshContext = context
        refreshContext.cursorOffset = location
        let generation = requestGeneration
        let provider = lspProvider
        serverList.refreshTask = Task { @MainActor [weak self, weak textView] in
            guard let textView else { return }
            let fresh = await provider.candidates(for: refreshContext, textView: textView)
            guard let self, !Task.isCancelled, self.requestGeneration == generation, !fresh.isEmpty else {
                return
            }
            self.serverList.isIncomplete = provider.lastListIsIncomplete
            self.replaceServerCandidates(with: fresh)
            self.serverList.isApplyingRefresh = true
            textView.refreshCodeCompletions()
            self.serverList.isApplyingRefresh = false
        }
    }

    /// Replaces the language server's candidates in the pool, including a late first answer not merged
    /// yet, with `fresh`.
    func replaceServerCandidates(with fresh: [CompletionCandidate]) {
        let provider = lspProvider
        rawCandidates.removeAll { candidateOwners[$0.id] === provider }
        candidateOwners = candidateOwners.filter { $0.value !== provider }
        lateResults.removeAll { $0.provider === provider }
        for candidate in fresh { candidateOwners[candidate.id] = provider }
        rawCandidates.append(contentsOf: fresh)
    }
}
