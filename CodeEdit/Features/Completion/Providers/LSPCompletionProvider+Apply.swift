//
//  LSPCompletionProvider+Apply.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import LanguageServerProtocol

// MARK: - Apply

extension LSPCompletionProvider {
    /// Whether the item should be resolved before it is applied: the user wants additional edits, the
    /// server offers none yet, supports resolving, and this item has not been resolved.
    func needsResolveBeforeApply(_ item: CompletionItem, candidateID: String) -> Bool {
        guard Settings[\.textEditing].completion.applyAdditionalEdits,
              item.additionalTextEdits == nil,
              !resolvedCandidateIDs.contains(candidateID),
              let client = languageClient() else {
            return false
        }
        return client.serverCapabilities.completionProvider?.resolveProvider == true
    }

    /// How long accepting an item waits for `completionItem/resolve` before applying it as it is.
    static let resolveTimeout: Duration = .milliseconds(300)

    /// Resolves `item`, giving up after ``resolveTimeout``.
    func resolveForApply(_ item: CompletionItem, candidateID: String) async -> CompletionItem {
        resolvedCandidateIDs.insert(candidateID)
        guard let client = languageClient() else { return item }
        let resolved = await withTaskGroup(of: CompletionItem?.self) { group in
            group.addTask { await self.resolveIfSupported(item, client: client) }
            group.addTask {
                try? await Task.sleep(for: Self.resolveTimeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let resolved else { return item }
        itemsByCandidateID[candidateID] = resolved
        return resolved
    }

    /// Applies `item`: its primary edit plus, when enabled, its `additionalTextEdits`, as one undo step.
    func apply(item: CompletionItem, textView: TextViewController, cursorPosition: CursorPosition?) {
        guard let primary = primaryEdit(for: item, textView: textView, cursorPosition: cursorPosition) else {
            return
        }
        let additional = Settings[\.textEditing].completion.applyAdditionalEdits
            ? additionalEdits(for: item, textView: textView)
            : []
        let plan = CompletionEditPlanner.plan(primary: primary.range, additional: additional)

        let undoManager = textView.textView.undoManager
        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }
        for edit in plan.additional {
            textView.textView.replaceCharacters(in: edit.range, with: edit.newText)
        }
        if primary.isSnippet {
            textView.insertSnippet(primary.newText, replacing: plan.primaryRange)
        } else {
            textView.textView.replaceCharacters(in: plan.primaryRange, with: primary.newText)
        }
    }

    /// The edit that completes the symbol under the cursor.
    struct PrimaryEdit {
        var range: NSRange
        var newText: String
        var isSnippet: Bool
    }

    func primaryEdit(
        for item: CompletionItem,
        textView: TextViewController,
        cursorPosition: CursorPosition?
    ) -> PrimaryEdit? {
        if let textEdit = item.textEdit {
            return textEditPrimary(textEdit, item: item, textView: textView, cursorPosition: cursorPosition)
        }
        return insertTextPrimary(item: item, textView: textView, cursorPosition: cursorPosition)
    }

    func textEditPrimary(
        _ textEdit: TwoTypeOption<TextEdit, InsertReplaceEdit>,
        item: CompletionItem,
        textView: TextViewController,
        cursorPosition: CursorPosition?
    ) -> PrimaryEdit? {
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
        guard var range = textView.textView.nsRangeFrom(lspRange: lspRange) else { return nil }
        // The server's edit predates any prefix typed while filtering the cached suggestions.
        if let requestOffset, let cursorPosition,
           let current = textView.resolveCursorPosition(cursorPosition),
           range.location <= requestOffset, range.max >= requestOffset,
           current.range.location >= requestOffset {
            range.length += current.range.location - requestOffset
        }
        return PrimaryEdit(range: range, newText: newText, isSnippet: item.insertTextFormat == .snippet)
    }

    func insertTextPrimary(
        item: CompletionItem,
        textView: TextViewController,
        cursorPosition: CursorPosition?
    ) -> PrimaryEdit? {
        guard let cursorPosition,
              let resolved = textView.resolveCursorPosition(cursorPosition) else {
            return nil
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
        return PrimaryEdit(
            range: NSRange(location: wordStart, length: location - wordStart),
            newText: insertText,
            isSnippet: isSnippet
        )
    }

    /// The item's `additionalTextEdits` in document coordinates. Edits the text view cannot map are skipped.
    func additionalEdits(for item: CompletionItem, textView: TextViewController) -> [CompletionTextEdit] {
        (item.additionalTextEdits ?? []).compactMap { edit in
            guard let range = textView.textView.nsRangeFrom(lspRange: edit.range) else { return nil }
            return CompletionTextEdit(range: range, newText: edit.newText)
        }
    }
}
