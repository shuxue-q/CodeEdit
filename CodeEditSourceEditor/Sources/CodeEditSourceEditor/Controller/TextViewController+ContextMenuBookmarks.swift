//
//  TextViewController+ContextMenuBookmarks.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit on 2024.
//

import AppKit
import SwiftUI
import CodeEditTextView

extension TextViewController {

    // MARK: - Bookmarks

    /// Adds a bookmark for the specified line.
    /// - Parameter lineNumber: 1-indexed line number.
    public func bookmarkLine(at lineNumber: Int) {
        if contextMenuDelegate?.bookmarkLine(line: lineNumber) != true {
            guard let fileURL = fileURL else { return }
            let fileName = fileURL.lastPathComponent
            let lineIdx = max(0, lineNumber - 1)
            let lineText = textView.layoutManager.textLineForIndex(lineIdx).map {
                (textView.textStorage.string as NSString).substring(with: $0.range)
            }
            EditorBookmarkManager.shared.addBookmark(
                fileURL: fileURL,
                fileName: fileName,
                lineNumber: lineNumber,
                lineContent: lineText?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        BezelNotification.show(symbolName: "bookmark.fill", over: textView)
    }

    /// Adds a bookmark for the current file.
    public func bookmarkFile() {
        if contextMenuDelegate?.bookmarkFile() != true {
            guard let fileURL = fileURL else { return }
            EditorBookmarkManager.shared.addBookmark(
                fileURL: fileURL,
                fileName: fileURL.lastPathComponent,
                lineNumber: nil,
                lineContent: nil
            )
        }
        BezelNotification.show(symbolName: "bookmark.fill", over: textView)
    }

    // MARK: - Snippets

    /// Presents the Create Code Snippet sheet / window.
    func showCreateSnippetModal(code: String, line: Int) {
        guard let window = textView.window else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Create Code Snippet"
        panel.isFloatingPanel = true

        let snippetView = CreateCodeSnippetView(
            initialCode: code,
            onSave: { [weak panel, weak self] snippet in
                SnippetManager.shared.addSnippet(snippet)
                panel?.close()
                if let textView = self?.textView {
                    BezelNotification.show(symbolName: "curlybraces", over: textView)
                }
            },
            onCancel: { [weak panel] in
                panel?.close()
            }
        )

        panel.contentView = NSHostingView(rootView: snippetView)
        window.beginSheet(panel)
    }

    // MARK: - Refactoring Actions

    /// Renames the symbol under the cursor locally within the document.
    func renameSymbolAtCursor() {
        guard let word = currentWordUnderCursor(), !word.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Symbol"
        alert.informativeText = "Enter a new name for '\(word)':"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.stringValue = word
        alert.accessoryView = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newName = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newName.isEmpty && newName != word {
                performLocalRename(oldName: word, newName: newName)
            }
        }
    }

    /// Performs local symbol replacement across the document.
    func performLocalRename(oldName: String, newName: String) {
        guard isEditable else { return }
        let text = textView.string
        guard let regex = try? NSRegularExpression(
            pattern: "\\b\(NSRegularExpression.escapedPattern(for: oldName))\\b"
        ) else { return }
        let range = NSRange(location: 0, length: (text as NSString).length)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return }

        for match in matches.reversed() {
            textView.replaceCharacters(in: match.range, with: newName)
        }
        BezelNotification.show(symbolName: "character.cursor.ibeam", over: textView)
    }

    /// Extracts selected text to a function.
    func extractSelectionToFunction() {
        guard isEditable else { return }
        let selected = currentSelectedText()
        guard !selected.isEmpty, let selectionRange = textView.selectionManager.textSelections.first?.range else {
            return
        }

        let funcName = "extractedFunction"
        let funcCall = "\(funcName)()"
        let indent = "    "
        let newFunc = "\n\n\(indent)func \(funcName)() {\n\(indent)\(indent)\(selected)\n\(indent)}"

        textView.replaceCharacters(in: selectionRange, with: funcCall)
        let docEnd = (textView.textStorage.string as NSString).length
        textView.replaceCharacters(in: NSRange(location: docEnd, length: 0), with: newFunc)
        BezelNotification.show(symbolName: "curlybraces", over: textView)
    }

    /// Extracts selected text to a variable.
    func extractSelectionToVariable() {
        guard isEditable else { return }
        let selected = currentSelectedText()
        guard !selected.isEmpty, let selectionRange = textView.selectionManager.textSelections.first?.range else {
            return
        }

        let varName = "extracted"
        let lineIdx = max(0, currentCursorLine() - 1)
        guard let lineInfo = textView.layoutManager.textLineForIndex(lineIdx) else { return }
        let lineText = (textView.textStorage.string as NSString).substring(with: lineInfo.range)
        let indent = String(lineText.prefix { $0 == " " || $0 == "\t" })

        let varDecl = "\(indent)let \(varName) = \(selected)\n"
        textView.replaceCharacters(in: NSRange(location: lineInfo.range.lowerBound, length: 0), with: varDecl)
        let newSelectionLocation = selectionRange.location + (varDecl as NSString).length
        textView.replaceCharacters(
            in: NSRange(location: newSelectionLocation, length: selectionRange.length),
            with: varName
        )
        BezelNotification.show(symbolName: "character.cursor.ibeam", over: textView)
    }
}
