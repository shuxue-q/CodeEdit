//
//  LSPCompletionProvider.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/10/26.
//

import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import LanguageServerProtocol

/// Provides language-server powered completion candidates to ``CompletionAggregator``.
///
/// Forwards completion requests to the language server that manages the document (if any) and
/// applies the selected candidate back into the text view. Documents without a running language
/// server simply return no candidates.
@MainActor
final class LSPCompletionProvider: CompletionProvider {
    /// Characters that are considered part of a symbol when filtering and replacing completions.
    static let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$#"))

    let source: CompletionSource = .lsp
    /// The window waits this long for the server when nothing else was offered, then opens without it
    /// (or stays closed) and merges the answer on the next cursor move.
    let deadline: Duration = .milliseconds(800)
    /// A fast server still lands in the first list: wait this long for it even when snippets, keywords
    /// or words are already there.
    let graceDeadline: Duration = .milliseconds(150)

    private weak var document: CodeFileDocument?

    @LazyService private var lspService: LSPService

    /// The completion items from the last request, keyed by candidate id, so `resolve` can look
    /// the original item back up.
    var itemsByCandidateID: [String: CompletionItem] = [:]
    /// Candidate ids already sent through `completionItem/resolve`, so accepting one never waits again.
    var resolvedCandidateIDs: Set<String> = []
    /// The document offset the cursor was at when the last completion request was made, used to
    /// pad a server text-edit range by anything typed since.
    var requestOffset: Int?

    init(document: CodeFileDocument) {
        self.document = document
    }

    // MARK: - CompletionProvider

    func triggerCharacters() -> Set<String> {
        guard let client = languageClient(),
              let triggerCharacters = client.serverCapabilities.completionProvider?.triggerCharacters else {
            return []
        }
        return Set(triggerCharacters)
    }

    func candidates(for context: CompletionContext, textView: TextViewController) async -> [CompletionCandidate] {
        guard document?.languageServerURI != nil,
              languageClient() != nil,
              let position = textView.textView.lspPositionFrom(offset: context.cursorOffset) else {
            return []
        }

        do {
            let scoredItems = try await completionItems(
                textView: textView,
                position: position,
                location: context.cursorOffset
            )
            let items = scoredItems.map(\.item)
            // A newer request cancels this one; its state must not be overwritten by this stale answer.
            try Task.checkCancellation()
            requestOffset = context.cursorOffset
            itemsByCandidateID = [:]
            resolvedCandidateIDs = []
            let candidates = scoredItems.map { candidate(from: $0.item, score: $0.score) }
            for (item, candidate) in zip(items, candidates) {
                itemsByCandidateID[candidate.id] = item
            }
            return candidates
        } catch {
            return []
        }
    }

    func apply(_ candidate: CompletionCandidate, textView: TextViewController, cursorPosition: CursorPosition?) {
        apply(candidate, textView: textView, cursorPosition: cursorPosition, commitCharacter: nil)
    }

    func apply(
        _ candidate: CompletionCandidate,
        textView: TextViewController,
        cursorPosition: CursorPosition?,
        commitCharacter: Character?
    ) {
        guard case .lsp(let payloadItem) = candidate.payload else { return }
        // A resolved copy (documentation, additional edits) supersedes the payload the row was built with.
        let item = itemsByCandidateID[candidate.id] ?? payloadItem
        if needsResolveBeforeApply(item, candidateID: candidate.id) {
            // The server may only attach `additionalTextEdits` on resolve; wait briefly for them.
            Task { @MainActor [weak self, weak textView] in
                guard let self, let textView else { return }
                let resolved = await self.resolveForApply(item, candidateID: candidate.id)
                // The user may have kept typing while the server answered; apply at the current cursor.
                self.apply(
                    item: resolved,
                    textView: textView,
                    cursorPosition: textView.cursorPositions.first,
                    commitCharacter: commitCharacter
                )
            }
        } else {
            apply(item: item, textView: textView, cursorPosition: cursorPosition, commitCharacter: commitCharacter)
        }
    }

    func resolve(_ candidate: CompletionCandidate) async -> CompletionCandidate? {
        guard case .lsp(let item) = candidate.payload, let client = languageClient() else { return nil }
        let resolved = await resolveIfSupported(item, client: client)
        resolvedCandidateIDs.insert(candidate.id)
        let withOrigin = await attachDeclaringHeader(to: resolved, client: client)
        guard withOrigin != item else { return nil }
        itemsByCandidateID[candidate.id] = withOrigin
        resolvedCandidateIDs.insert(candidate.id)
        // Keep the same identity so the aggregator can find the row to replace.
        let updated = self.candidate(from: withOrigin)
        return CompletionCandidate(
            id: candidate.id,
            label: updated.label,
            filterText: updated.filterText,
            sortText: updated.sortText,
            score: updated.score,
            kind: updated.kind,
            source: updated.source,
            detail: updated.detail,
            documentation: updated.documentation,
            deprecated: updated.deprecated,
            payload: updated.payload
        )
    }

    // MARK: - Requesting

    /// A completion item with the relevance score the server attached to it, if any.
    typealias ScoredItem = (item: CompletionItem, score: Double?)

    /// Requests completions after pending edits have been sent.
    ///
    /// If the server has dropped the file, open it again with the current buffer and retry once.
    private func completionItems(
        textView: TextViewController,
        position: Position,
        location: Int
    ) async throws -> [ScoredItem] {
        guard let document,
              let uri = document.languageServerURI,
              let client = languageClient() else {
            throw CancellationError()
        }
        try await document.languageServerObjects.textCoordinator.flushPendingChanges()
        try Task.checkCancellation()
        do {
            let response = try await client.requestScoredCompletion(for: uri, position: position)
            return items(from: response, textView: textView, position: position, location: location)
        } catch {
            guard LSPService.LanguageServerType.isNonAddedDocument(error) else { throw error }
            try await client.reopenDocument(document)
            try Task.checkCancellation()
            let response = try await client.requestScoredCompletion(for: uri, position: position)
            return items(from: response, textView: textView, position: position, location: location)
        }
    }

    private func items(
        from response: ScoredCompletionResponse,
        textView: TextViewController,
        position: Position,
        location: Int
    ) -> [ScoredItem] {
        let string = textView.textView.textStorage.string as NSString
        let scored = zip(response.items, response.scores).map { (item: $0, score: $1) }
        return augmentIncludeCompletions(
            items: scored,
            textView: textView,
            position: position,
            location: location,
            string: string
        )
    }

    /// Maps an LSP completion item to a pipeline candidate.
    private func candidate(from item: CompletionItem, score: Double? = nil) -> CompletionCandidate {
        let entry = LSPCompletionEntry(item: item)
        return CompletionCandidate(
            id: "lsp.\(UUID().uuidString)",
            label: entry.label,
            filterText: item.filterText ?? entry.label,
            sortText: item.sortText,
            score: score,
            kind: LSPCompletionEntry.category(for: item),
            source: .lsp,
            detail: entry.detail,
            documentation: entry.documentation,
            deprecated: entry.deprecated,
            payload: .lsp(item)
        )
    }

    // MARK: - Helpers

    /// The language client managing this provider's document, if one is running.
    func languageClient() -> LSPService.LanguageServerType? {
        guard let fileURL = document?.fileURL else { return nil }
        return lspService.languageClient(forDocument: fileURL)
    }
}

// MARK: - Preprocessor Helpers

extension LSPCompletionProvider {
    /// Augments completion items with `#include` options when completing preprocessor lines.
    private func augmentIncludeCompletions(
        items: [ScoredItem],
        textView: TextViewController,
        position: Position,
        location: Int,
        string: NSString
    ) -> [ScoredItem] {
        var lineStart = location
        while lineStart > 0 && string.character(at: lineStart - 1) != 0x0A {
            lineStart -= 1
        }
        let lineText = string.substring(with: NSRange(location: lineStart, length: location - lineStart))
        let trimmed = lineText.trimmingCharacters(in: .whitespaces)

        guard trimmed.hasPrefix("#") else { return items }
        if trimmed.hasPrefix("#include ") || trimmed.hasPrefix("#include<") || trimmed.hasPrefix("#include\"") {
            return items
        }

        guard let hashRange = lineText.range(of: "#") else { return items }
        let hashOffsetInLine = lineText.distance(from: lineText.startIndex, to: hashRange.lowerBound)
        let hashLocation = lineStart + hashOffsetInLine
        let replaceStart = textView.textView.lspPositionFrom(offset: hashLocation + 1) ?? position
        let editRange = LSPRange(start: replaceStart, end: position)

        let includeAngle = CompletionItem(
            label: "#include <insert>",
            kind: .snippet,
            detail: "Include system header",
            insertText: "include <$0>",
            insertTextFormat: .snippet,
            textEdit: .optionA(TextEdit(range: editRange, newText: "include <$0>"))
        )
        let includeQuote = CompletionItem(
            label: "#include \"insert\"",
            kind: .snippet,
            detail: "Include user header",
            insertText: "include \"$0\"",
            insertTextFormat: .snippet,
            textEdit: .optionA(TextEdit(range: editRange, newText: "include \"$0\""))
        )

        let remaining = items.filter { scored in
            let label = scored.item.label.trimmingCharacters(in: .whitespaces)
            return label != "include" && !label.hasPrefix("#include")
        }

        return [(item: includeAngle, score: nil), (item: includeQuote, score: nil)] + remaining
    }
}
