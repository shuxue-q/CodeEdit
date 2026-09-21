//
//  LSPCompletionDelegate.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/10/26.
//

import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import LanguageServerProtocol

/// Provides language-server powered completions to the source editor's suggestion window.
///
/// This delegate is installed on every ``CodeFileView``. It forwards completion requests to the
/// language server that manages the document (if any) and applies the selected completion item
/// back into the text view. Documents without a running language server simply return `nil`,
/// which keeps the suggestion window closed.
@MainActor
final class LSPCompletionDelegate: CodeSuggestionDelegate {
    /// Characters that are considered part of a symbol when filtering and replacing completions.
    private static let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$#"))

    private weak var document: CodeFileDocument?

    @LazyService private var lspService: LSPService

    /// The completion items from the last request, kept for synchronous filtering and applying.
    private var cachedEntries: [LSPCompletionEntry] = []
    /// The document offset the cursor was at when the last completion request was made.
    private var requestOffset: Int?

    init(document: CodeFileDocument) {
        self.document = document
    }

    // MARK: - CodeSuggestionDelegate

    func completionTriggerCharacters() -> Set<String> {
        guard let client = languageClient(),
              let triggerCharacters = client.serverCapabilities.completionProvider?.triggerCharacters else {
            return []
        }
        return Set(triggerCharacters)
    }

    func completionSuggestionsRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])? {
        guard let document,
              let uri = document.languageServerURI,
              let client = languageClient(),
              let resolved = textView.resolveCursorPosition(cursorPosition),
              let position = textView.textView.lspPositionFrom(offset: resolved.range.location) else {
            return nil
        }

        do {
            try await document.languageServerObjects.textCoordinator.flushPendingChanges()
            try Task.checkCancellation()
            let response = try await client.requestCompletion(
                for: uri,
                position: position,
                bypassCache: true
            )
            try Task.checkCancellation()
            let rawItems = response?.items ?? []
            let string = textView.textView.textStorage.string as NSString
            let augmented = augmentIncludeCompletions(
                items: rawItems,
                textView: textView,
                position: position,
                location: resolved.range.location,
                string: string
            )
            let entries = augmented.map { LSPCompletionEntry(item: $0) }
            cachedEntries = entries
            requestOffset = resolved.range.location
            return (cursorPosition, entries)
        } catch {
            return nil
        }
    }

    func completionOnCursorMove(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) -> [CodeSuggestionEntry]? {
        guard !cachedEntries.isEmpty,
              let requestOffset,
              let resolved = textView.resolveCursorPosition(cursorPosition) else {
            return nil
        }
        let location = resolved.range.location
        let string = textView.textView.textStorage.string as NSString
        // The cursor moved before the offset completions were requested at, the cache is stale.
        guard location >= requestOffset, location <= string.length else {
            return nil
        }
        // Nothing was typed since the request, keep showing the cached items.
        guard location > requestOffset else {
            return cachedEntries
        }

        guard let wordStart = symbolStart(in: string, at: location, requestOffset: requestOffset) else {
            return nil
        }

        let prefix = string.substring(with: NSRange(location: wordStart, length: location - wordStart))
        let trimmedPrefix = prefix.hasPrefix("#") ? String(prefix.dropFirst()) : prefix
        let filtered = cachedEntries.filter { entry in
            matchesPrefix(entry: entry, prefix: prefix, trimmedPrefix: trimmedPrefix)
        }
        return filtered.isEmpty ? nil : filtered
    }

    private func symbolStart(in string: NSString, at location: Int, requestOffset: Int) -> Int? {
        var wordStart = location
        while wordStart > 0,
              let scalar = Unicode.Scalar(string.character(at: wordStart - 1)),
              Self.wordCharacters.contains(scalar) {
            wordStart -= 1
        }
        guard wordStart < location else { return nil }

        if wordStart >= requestOffset {
            let typedRange = NSRange(location: requestOffset, length: wordStart - requestOffset)
            if typedRange.length > 0,
               string.substring(with: typedRange).rangeOfCharacter(from: Self.wordCharacters.inverted) != nil {
                return nil
            }
        }
        return wordStart
    }

    private func matchesPrefix(entry: LSPCompletionEntry, prefix: String, trimmedPrefix: String) -> Bool {
        let candidate = entry.item.filterText ?? entry.label
        let trimmed = candidate.trimmingCharacters(in: .whitespaces)
        if candidate.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil
            || trimmed.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil {
            return true
        }
        if !trimmedPrefix.isEmpty {
            if trimmed.range(of: trimmedPrefix, options: [.caseInsensitive, .anchored]) != nil {
                return true
            }
            if trimmed.hasPrefix("#") {
                let withoutHash = String(trimmed.dropFirst())
                if withoutHash.range(of: trimmedPrefix, options: [.caseInsensitive, .anchored]) != nil {
                    return true
                }
            }
            if let insertText = entry.item.insertText,
               insertText.range(of: trimmedPrefix, options: [.caseInsensitive, .anchored]) != nil {
                return true
            }
        }
        return prefix == "#"
    }

    func completionWindowApplyCompletion(
        item: CodeSuggestionEntry,
        textView: TextViewController,
        cursorPosition: CursorPosition?
    ) {
        guard let entry = item as? LSPCompletionEntry else { return }
        if let textEdit = entry.item.textEdit {
            applyTextEdit(textEdit, item: entry.item, textView: textView, cursorPosition: cursorPosition)
        } else {
            applyInsertText(item: entry.item, textView: textView, cursorPosition: cursorPosition)
        }
    }

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
        let (stripped, cursorOffset) = Self.parseSnippet(text: newText, format: item.insertTextFormat)
        textView.textView.replaceCharacters(in: range, with: stripped)
        if let cursorOffset {
            let targetLocation = range.location + cursorOffset
            textView.textView.selectionManager.setSelectedRange(NSRange(location: targetLocation, length: 0))
            textView.textView.scrollSelectionToVisible()
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
        let (insertText, cursorOffset) = Self.parseSnippet(
            text: item.insertText ?? item.label,
            format: item.insertTextFormat
        )
        if wordStart < location,
           string.character(at: wordStart) == 0x23, // '#'
           !insertText.hasPrefix("#") {
            wordStart += 1
        }
        let replaceRange = NSRange(location: wordStart, length: location - wordStart)
        textView.textView.replaceCharacters(in: replaceRange, with: insertText)
        if let cursorOffset {
            let targetLocation = replaceRange.location + cursorOffset
            textView.textView.selectionManager.setSelectedRange(NSRange(location: targetLocation, length: 0))
            textView.textView.scrollSelectionToVisible()
        }
    }

    func completionWindowDidClose() {
        cachedEntries = []
        requestOffset = nil
    }

    // MARK: - Helpers

    /// The language client managing this delegate's document, if one is running.
    private func languageClient() -> LSPService.LanguageServerType? {
        guard let fileURL = document?.fileURL else { return nil }
        return lspService.languageClient(forDocument: fileURL)
    }
}

// MARK: - Snippet & Preprocessor Helpers

extension LSPCompletionDelegate {
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

    /// Parses snippet syntax to plain text and returns the offset of the first tab stop ($0 or $1).
    private static func parseSnippet(
        text: String,
        format: InsertTextFormat?
    ) -> (stripped: String, cursorOffset: Int?) {
        guard format == .snippet else { return (text, nil) }

        var cursorOffset: Int?
        if let tabStopRange = text.range(of: #"\$(?:0|\{0\}|1|\{1(?::[^}]*)?\})"#, options: .regularExpression) {
            let prefix = String(text[..<tabStopRange.lowerBound])
            let cleanPrefix = stripSnippetSyntax(from: prefix, format: .snippet)
            cursorOffset = (cleanPrefix as NSString).length
        }

        let stripped = stripSnippetSyntax(from: text, format: .snippet)
        return (stripped, cursorOffset)
    }

    /// Converts snippet syntax into plain text, replacing `${n:placeholder}` with the placeholder
    /// and removing `$n` / `${n}` tab stops.
    private static func stripSnippetSyntax(from text: String, format: InsertTextFormat?) -> String {
        guard format == .snippet else { return text }
        var result = text
        // swiftlint:disable force_try
        let placeholderPattern = try! NSRegularExpression(pattern: #"\$\{\d+:([^}]*)\}"#)
        let tabStopPattern = try! NSRegularExpression(pattern: #"\$\{\d+\}|\$\d+"#)
        // swiftlint:enable force_try
        result = placeholderPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "$1"
        )
        result = tabStopPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: ""
        )
        return result
    }
}
