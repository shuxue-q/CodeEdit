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
    /// Whether the server marked its last list incomplete: typing more should ask it again instead of
    /// only filtering what it sent. Reset when a new request starts.
    private(set) var lastListIsIncomplete = false
    /// The `labelDetails` of the items from the last request, keyed by candidate id, so a resolved
    /// item keeps the detail it was shown with.
    var labelDetailsByCandidateID: [String: CompletionLabelDetails] = [:]

    /// Languages whose server's incomplete lists are re-requested as the prefix grows, and whose
    /// `labelDetails` fill an empty detail. The Dart analysis server marks a list incomplete when it
    /// hits the item cap, and sends the signature and declaring library only in `labelDetails`.
    /// rust-analyzer marks every list incomplete (it filters by the prefix, and items from modules the
    /// file does not import yet depend on it) and sends no `detail` at all: the signature is in
    /// `labelDetails.description`, the `(use std::…)` an item would add in `labelDetails.detail`.
    /// clangd's lists are complete unless they hit its result limit, and it already fills `detail`, so
    /// the C family and CMake keep filtering the first list client-side and showing `detail` alone.
    static let incompleteListLanguageIds: Set<String> = DartKeywords.languageIds.union(RustKeywords.languageIds)

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
        lastListIsIncomplete = false
        guard document?.languageServerURI != nil,
              languageClient() != nil,
              let position = textView.textView.lspPositionFrom(offset: context.cursorOffset) else {
            return []
        }

        do {
            let response = try await completionItems(
                textView: textView,
                position: position,
                location: context.cursorOffset
            )
            // A newer request cancels this one; its state must not be overwritten by this stale answer.
            try Task.checkCancellation()
            requestOffset = context.cursorOffset
            lastListIsIncomplete = response.isIncomplete
            itemsByCandidateID = [:]
            labelDetailsByCandidateID = [:]
            resolvedCandidateIDs = []
            let showsLabelDetails = Self.incompleteListLanguageIds.contains(context.languageId)
            var candidates: [CompletionCandidate] = []
            for scored in response.items {
                let labelDetails = showsLabelDetails ? scored.labelDetails : nil
                let mapped = self.candidate(from: scored.item, score: scored.score, labelDetails: labelDetails)
                itemsByCandidateID[mapped.id] = scored.item
                labelDetailsByCandidateID[mapped.id] = labelDetails
                candidates.append(mapped)
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
        let updated = self.candidate(from: withOrigin, labelDetails: labelDetailsByCandidateID[candidate.id])
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

    /// A completion item with the relevance score and label details the server attached to it, if any.
    struct ScoredItem {
        /// The item as the server sent it.
        let item: CompletionItem
        /// The server's relevance score (clangd), if any.
        var score: Double?
        /// The item's `labelDetails`, if any.
        var labelDetails: CompletionLabelDetails?
    }

    /// The items of one completion answer, and whether the server marked the list incomplete.
    typealias ScoredList = (items: [ScoredItem], isIncomplete: Bool)

    /// Requests completions after pending edits have been sent.
    ///
    /// If the server has dropped the file, open it again with the current buffer and retry once.
    private func completionItems(
        textView: TextViewController,
        position: Position,
        location: Int
    ) async throws -> ScoredList {
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
    ) -> ScoredList {
        let string = textView.textView.textStorage.string as NSString
        let scored = response.items.indices.map { index in
            ScoredItem(
                item: response.items[index],
                score: response.scores.indices.contains(index) ? response.scores[index] : nil,
                labelDetails: response.labelDetails.indices.contains(index) ? response.labelDetails[index] : nil
            )
        }
        let items = augmentIncludeCompletions(
            items: scored,
            textView: textView,
            position: position,
            location: location,
            string: string
        )
        return (items, response.isIncomplete)
    }

    /// Maps an LSP completion item to a pipeline candidate. `labelDetails` fill the detail when the
    /// item has none.
    private func candidate(
        from item: CompletionItem,
        score: Double? = nil,
        labelDetails: CompletionLabelDetails? = nil
    ) -> CompletionCandidate {
        let entry = LSPCompletionEntry(item: item)
        let detail = entry.detail.flatMap { $0.isEmpty ? nil : $0 } ?? labelDetails?.displayText
        return CompletionCandidate(
            id: "lsp.\(UUID().uuidString)",
            label: entry.label,
            filterText: item.filterText ?? entry.label,
            sortText: item.sortText,
            score: score,
            kind: LSPCompletionEntry.category(for: item),
            source: .lsp,
            detail: detail,
            documentation: entry.documentation,
            deprecated: entry.deprecated,
            payload: .lsp(item)
        )
    }

    // MARK: - Helpers

    /// A scratch document on this provider's language server for chain completion, if one is running.
    func makeChainScratchServer(for document: CodeFileDocument) -> ChainScratchServer? {
        guard let client = languageClient(), let uri = document.languageServerURI else { return nil }
        return LSPChainScratchServer(client: client, documentURI: uri, languageId: document.getLanguage().id.rawValue)
    }

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
            detail: String(localized: "Include system header"),
            insertText: "include <$0>",
            insertTextFormat: .snippet,
            textEdit: .optionA(TextEdit(range: editRange, newText: "include <$0>"))
        )
        let includeQuote = CompletionItem(
            label: "#include \"insert\"",
            kind: .snippet,
            detail: String(localized: "Include user header"),
            insertText: "include \"$0\"",
            insertTextFormat: .snippet,
            textEdit: .optionA(TextEdit(range: editRange, newText: "include \"$0\""))
        )

        let remaining = items.filter { scored in
            let label = scored.item.label.trimmingCharacters(in: .whitespaces)
            return label != "include" && !label.hasPrefix("#include")
        }

        return [
            ScoredItem(item: includeAngle),
            ScoredItem(item: includeQuote)
        ] + remaining
    }
}
