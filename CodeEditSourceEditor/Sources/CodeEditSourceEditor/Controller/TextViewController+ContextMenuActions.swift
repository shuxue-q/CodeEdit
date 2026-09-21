//
//  TextViewController+ContextMenuActions.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit on 2024.
//

import AppKit
import SwiftUI
import CodeEditTextView

extension TextViewController {

    // MARK: - Action Selectors

    @objc
    func contextMenuCreateSnippet(_ sender: Any?) {
        let line = (sender as? NSMenuItem)?.representedObject as? Int ?? currentCursorLine()
        let selected = currentSelectedText()
        let code = selected.isEmpty ? (currentLineText() ?? "") : selected

        if contextMenuDelegate?.createCodeSnippet(text: code, line: line) != true {
            showCreateSnippetModal(code: code, line: line)
        }
    }

    @objc
    func contextMenuShowCodingTools(_ sender: Any?) {
        if contextMenuDelegate?.showCodingTools() != true {
            if #available(macOS 15.0, *) {
                NSApp.sendAction(NSSelectorFromString("showWritingTools:"), to: nil, from: textView)
            } else {
                BezelNotification.show(symbolName: "sparkles", over: textView)
            }
        }
    }

    @objc
    func contextMenuCodingToolProofread(_ sender: Any?) {
        BezelNotification.show(symbolName: "text.badge.checkmark", over: textView)
    }

    @objc
    func contextMenuCodingToolRewrite(_ sender: Any?) {
        BezelNotification.show(symbolName: "pencil.and.outline", over: textView)
    }

    @objc
    func contextMenuCodingToolSummary(_ sender: Any?) {
        BezelNotification.show(symbolName: "list.bullet.rectangle", over: textView)
    }

    @objc
    func contextMenuCodingToolExplain(_ sender: Any?) {
        BezelNotification.show(symbolName: "sparkles", over: textView)
    }

    @objc
    func contextMenuCodingToolTests(_ sender: Any?) {
        BezelNotification.show(symbolName: "checkmark.seal", over: textView)
    }

    @objc
    func contextMenuRefactorRename(_ sender: Any?) {
        if contextMenuDelegate?.refactorRename() != true {
            renameSymbolAtCursor()
        }
    }

    @objc
    func contextMenuRefactorExtractFunction(_ sender: Any?) {
        if contextMenuDelegate?.refactorExtractFunction() != true {
            extractSelectionToFunction()
        }
    }

    @objc
    func contextMenuRefactorExtractVariable(_ sender: Any?) {
        if contextMenuDelegate?.refactorExtractVariable() != true {
            extractSelectionToVariable()
        }
    }

    @objc
    func contextMenuRefactorAddMissingSwitchCases(_ sender: Any?) {
        if contextMenuDelegate?.refactorAddMissingSwitchCases() != true {
            BezelNotification.show(symbolName: "arrow.triangle.branch", over: textView)
        }
    }

    @objc
    func contextMenuRefactorGenerateMemberwiseInit(_ sender: Any?) {
        if contextMenuDelegate?.refactorGenerateMemberwiseInit() != true {
            BezelNotification.show(symbolName: "curlybraces", over: textView)
        }
    }

    @objc
    func contextMenuRefactorFormatDocument(_ sender: Any?) {
        if contextMenuDelegate?.refactorFormatDocument() != true {
            BezelNotification.show(symbolName: "text.alignleft", over: textView)
        }
    }

    @objc
    func contextMenuFindInWorkspace(_ sender: Any?) {
        if let contextMenuDelegate {
            contextMenuDelegate.findInWorkspace(query: nil)
        } else {
            NSApp.sendAction(NSSelectorFromString("openSearchNavigator:"), to: nil, from: nil)
        }
    }

    @objc
    func contextMenuFindSelectedTextInWorkspace(_ sender: Any?) {
        let selected = currentSelectedText()
        let query = selected.isEmpty ? (currentWordUnderCursor() ?? "") : selected
        if let contextMenuDelegate {
            contextMenuDelegate.findInWorkspace(query: query)
        } else {
            NSApp.sendAction(NSSelectorFromString("openSearchNavigator:"), to: nil, from: nil)
        }
    }

    @objc
    func contextMenuFindSelectedSymbolInWorkspace(_ sender: Any?) {
        let word = currentWordUnderCursor() ?? ""
        if let contextMenuDelegate {
            contextMenuDelegate.findInWorkspace(query: word)
        } else {
            NSApp.sendAction(NSSelectorFromString("openSearchNavigator:"), to: nil, from: nil)
        }
    }

    @objc
    func contextMenuFindCallHierarchy(_ sender: Any?) {
        contextMenuDelegate?.findCallHierarchy()
    }

    @objc
    func contextMenuFindInFile(_ sender: Any?) {
        findViewController?.showFindPanel()
    }

    @objc
    func contextMenuFindAndReplace(_ sender: Any?) {
        findViewController?.showFindPanel()
        findViewController?.viewModel.mode = .replace
    }

    @objc
    func contextMenuFindNext(_ sender: Any?) {
        findViewController?.viewModel.moveToNextMatch()
    }

    @objc
    func contextMenuFindPrevious(_ sender: Any?) {
        findViewController?.viewModel.moveToPreviousMatch()
    }

    @objc
    func contextMenuUseSelectionForFind(_ sender: Any?) {
        let text = currentSelectedText()
        if !text.isEmpty {
            findViewController?.viewModel.findText = text
        }
    }

    @objc
    func contextMenuUseSelectionForReplace(_ sender: Any?) {
        let text = currentSelectedText()
        if !text.isEmpty {
            findViewController?.viewModel.replaceText = text
        }
    }

    @objc
    func contextMenuJumpToSelection(_ sender: Any?) {
        textView.scrollSelectionToVisible()
    }

    @objc
    func contextMenuJumpToDefinition(_ sender: Any?) {
        let selection = textView.selectionManager.textSelections.first?.range
            ?? NSRange(location: 0, length: 0)
        jumpToDefinitionModel?.performJump(at: selection)
    }

    @objc
    func contextMenuJumpToTypeDefinition(_ sender: Any?) {
        contextMenuDelegate?.jumpToTypeDefinition()
    }

    @objc
    func contextMenuRevealInProjectNavigator(_ sender: Any?) {
        if let contextMenuDelegate {
            contextMenuDelegate.revealInProjectNavigator()
        } else {
            NSApp.sendAction(NSSelectorFromString("revealFile:"), to: nil, from: nil)
        }
    }

    @objc
    func contextMenuJumpToNextCounterpart(_ sender: Any?) {
        contextMenuDelegate?.jumpToNextCounterpart()
    }

    @objc
    func contextMenuJumpToPreviousCounterpart(_ sender: Any?) {
        contextMenuDelegate?.jumpToPreviousCounterpart()
    }

    @objc
    func contextMenuShowPreviousTab(_ sender: Any?) {
        contextMenuDelegate?.showPreviousTab()
    }

    @objc
    func contextMenuShowNextTab(_ sender: Any?) {
        contextMenuDelegate?.showNextTab()
    }

    @objc
    func contextMenuGoBack(_ sender: Any?) {
        contextMenuDelegate?.navigateGoBack()
    }

    @objc
    func contextMenuGoForward(_ sender: Any?) {
        contextMenuDelegate?.navigateGoForward()
    }

    @objc
    func contextMenuFoldToggle(_ sender: Any?) {
        let lineNumber = (sender as? NSMenuItem)?.representedObject as? Int ?? currentCursorLine()
        toggleFold(at: lineNumber)
    }

    @objc
    func contextMenuAddDocumentation(_ sender: Any?) {
        let lineNumber = (sender as? NSMenuItem)?.representedObject as? Int ?? currentCursorLine()
        addDocumentation(at: lineNumber)
    }

    @objc
    func contextMenuShowLastChange(_ sender: Any?) {
        let lineNumber = (sender as? NSMenuItem)?.representedObject as? Int ?? currentCursorLine()
        showLastChange(at: lineNumber)
    }

    @objc
    func contextMenuBookmarkLine(_ sender: Any?) {
        let lineNumber = (sender as? NSMenuItem)?.representedObject as? Int ?? currentCursorLine()
        bookmarkLine(at: lineNumber)
    }

    @objc
    func contextMenuBookmarkFile(_ sender: Any?) {
        bookmarkFile()
    }

    @objc
    func contextMenuAutoFillPasswords(_ sender: Any?) {
        BezelNotification.show(symbolName: "key.fill", over: textView)
    }

    @objc
    func contextMenuAutoFillContacts(_ sender: Any?) {
        BezelNotification.show(symbolName: "person.crop.circle", over: textView)
    }

    // MARK: - Text / Cursor Helpers

    /// Returns the 1-indexed line number for the first cursor position.
    public func currentCursorLine() -> Int {
        if let pos = cursorPositions.first {
            return pos.start.line
        }
        return 1
    }

    /// Returns the text of the line where the cursor is currently placed.
    public func currentLineText() -> String? {
        let lineIdx = max(0, currentCursorLine() - 1)
        guard let lineInfo = textView.layoutManager.textLineForIndex(lineIdx) else { return nil }
        return (textView.textStorage.string as NSString).substring(with: lineInfo.range)
    }

    /// Returns currently selected text in the text view, or empty string.
    public func currentSelectedText() -> String {
        guard let range = textView.selectionManager.textSelections.first?.range, range.length > 0 else {
            return ""
        }
        return (textView.textStorage.string as NSString).substring(with: range)
    }

    /// Returns the word under the current cursor.
    public func currentWordUnderCursor() -> String? {
        guard let range = textView.selectionManager.textSelections.first?.range else { return nil }
        let text = textView.textStorage.string as NSString
        guard text.length > 0 else { return nil }

        let location = min(range.location, text.length - 1)
        var wordStart = location
        var wordEnd = location

        let wordChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$"))

        while wordStart > 0 {
            let prevChar = text.character(at: wordStart - 1)
            guard let scalar = UnicodeScalar(prevChar), wordChars.contains(scalar) else { break }
            wordStart -= 1
        }

        while wordEnd < text.length {
            let nextChar = text.character(at: wordEnd)
            guard let scalar = UnicodeScalar(nextChar), wordChars.contains(scalar) else { break }
            wordEnd += 1
        }

        guard wordEnd > wordStart else { return nil }
        return text.substring(with: NSRange(location: wordStart, length: wordEnd - wordStart))
    }
}
