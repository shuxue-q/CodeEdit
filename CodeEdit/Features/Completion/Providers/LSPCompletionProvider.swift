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
    /// Zero: the window waits for the server, as it did before the aggregator existed.
    let deadline: Duration = .zero

    private weak var document: CodeFileDocument?

    @LazyService private var lspService: LSPService

    /// The completion items from the last request, keyed by candidate id, so `resolve` can look
    /// the original item back up.
    private var itemsByCandidateID: [String: CompletionItem] = [:]
    /// The document offset the cursor was at when the last completion request was made, used to
    /// pad a server text-edit range by anything typed since.
    private var requestOffset: Int?

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
            let items = try await completionItems(
                textView: textView,
                position: position,
                location: context.cursorOffset
            )
            requestOffset = context.cursorOffset
            itemsByCandidateID = [:]
            let candidates = items.map { candidate(from: $0) }
            for (item, candidate) in zip(items, candidates) {
                itemsByCandidateID[candidate.id] = item
            }
            return candidates
        } catch {
            return []
        }
    }

    func apply(_ candidate: CompletionCandidate, textView: TextViewController, cursorPosition: CursorPosition?) {
        guard case .lsp(let item) = candidate.payload else { return }
        if let textEdit = item.textEdit {
            applyTextEdit(textEdit, item: item, textView: textView, cursorPosition: cursorPosition)
        } else {
            applyInsertText(item: item, textView: textView, cursorPosition: cursorPosition)
        }
    }

    func resolve(_ candidate: CompletionCandidate) async -> CompletionCandidate? {
        guard case .lsp(let item) = candidate.payload, let client = languageClient() else { return nil }
        let resolved = await resolveIfSupported(item, client: client)
        let withOrigin = await attachDeclaringHeader(to: resolved, client: client)
        guard withOrigin != item else { return nil }
        itemsByCandidateID[candidate.id] = withOrigin
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

    /// Requests completions after pending edits have been sent.
    ///
    /// If the server has dropped the file, open it again with the current buffer and retry once.
    private func completionItems(
        textView: TextViewController,
        position: Position,
        location: Int
    ) async throws -> [CompletionItem] {
        guard let document,
              let uri = document.languageServerURI,
              let client = languageClient() else {
            throw CancellationError()
        }
        try await document.languageServerObjects.textCoordinator.flushPendingChanges()
        try Task.checkCancellation()
        do {
            let response = try await client.requestCompletion(for: uri, position: position, bypassCache: true)
            return items(from: response, textView: textView, position: position, location: location)
        } catch {
            guard LSPService.LanguageServerType.isNonAddedDocument(error) else { throw error }
            try await client.reopenDocument(document)
            try Task.checkCancellation()
            let response = try await client.requestCompletion(for: uri, position: position, bypassCache: true)
            return items(from: response, textView: textView, position: position, location: location)
        }
    }

    private func items(
        from response: CompletionResponse,
        textView: TextViewController,
        position: Position,
        location: Int
    ) -> [CompletionItem] {
        let rawItems = response?.items ?? []
        let string = textView.textView.textStorage.string as NSString
        return augmentIncludeCompletions(
            items: rawItems,
            textView: textView,
            position: position,
            location: location,
            string: string
        )
    }

    /// Maps an LSP completion item to a pipeline candidate.
    private func candidate(from item: CompletionItem) -> CompletionCandidate {
        let entry = LSPCompletionEntry(item: item)
        return CompletionCandidate(
            id: "lsp.\(UUID().uuidString)",
            label: entry.label,
            filterText: item.filterText ?? entry.label,
            sortText: item.sortText,
            kind: LSPCompletionEntry.category(for: item),
            source: .lsp,
            detail: entry.detail,
            documentation: entry.documentation,
            deprecated: entry.deprecated,
            payload: .lsp(item)
        )
    }

    // MARK: - Apply

    private func applyTextEdit(
        _ textEdit: TwoTypeOption<TextEdit, InsertReplaceEdit>,
        item: CompletionItem,
        textView: TextViewController,
        cursorPosition: CursorPosition?
    ) {
        let lspRange: LSPRange
        let newText: String
        switch textEdit {
        case .optionA(let edit):
            lspRange = edit.range
            newText = edit.newText
        case .optionB(let insertReplaceEdit):
            lspRange = insertReplaceEdit.insert
            newText = insertReplaceEdit.newText
        }
        guard var range = textView.textView.nsRangeFrom(lspRange: lspRange) else { return }
        // The server's edit predates any prefix typed while filtering the cached suggestions.
        if let requestOffset, let cursorPosition,
           let current = textView.resolveCursorPosition(cursorPosition),
           range.location <= requestOffset, range.max >= requestOffset,
           current.range.location >= requestOffset {
            range.length += current.range.location - requestOffset
        }
        if item.insertTextFormat == .snippet {
            textView.insertSnippet(newText, replacing: range)
        } else {
            textView.textView.replaceCharacters(in: range, with: newText)
        }
    }

    private func applyInsertText(
        item: CompletionItem,
        textView: TextViewController,
        cursorPosition: CursorPosition?
    ) {
        guard let cursorPosition,
              let resolved = textView.resolveCursorPosition(cursorPosition) else {
            return
        }
        let location = resolved.range.location
        let string = textView.textView.textStorage.string as NSString
        var wordStart = location
        while wordStart > 0,
              let scalar = Unicode.Scalar(string.character(at: wordStart - 1)),
              Self.wordCharacters.contains(scalar) {
            wordStart -= 1
        }
        let insertText = item.insertText ?? item.label
        let isSnippet = item.insertTextFormat == .snippet
        let plainText = isSnippet ? SnippetParser.plainText(insertText) : insertText
        if wordStart < location,
           string.character(at: wordStart) == 0x23, // '#'
           !plainText.hasPrefix("#") {
            wordStart += 1
        }
        let replaceRange = NSRange(location: wordStart, length: location - wordStart)
        if isSnippet {
            textView.insertSnippet(insertText, replacing: replaceRange)
        } else {
            textView.textView.replaceCharacters(in: replaceRange, with: insertText)
        }
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
        items: [CompletionItem],
        textView: TextViewController,
        position: Position,
        location: Int,
        string: NSString
    ) -> [CompletionItem] {
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

        let remaining = items.filter { item in
            let label = item.label.trimmingCharacters(in: .whitespaces)
            return label != "include" && !label.hasPrefix("#include")
        }

        return [includeAngle, includeQuote] + remaining
    }
}
