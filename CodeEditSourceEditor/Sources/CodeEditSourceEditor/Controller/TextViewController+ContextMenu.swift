//
//  TextViewController+ContextMenu.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit on 2024.
//

import AppKit
import SwiftUI
import CodeEditTextView

extension TextViewController {

    /// Builds the context menu for right-clicking in the editor, matching Xcode's context menu.
    /// - Parameter event: The mouse event that triggered the menu.
    /// - Returns: The configured context menu.
    public func buildContextMenu(for event: NSEvent) -> NSMenu {
        let point = textView.convert(event.locationInWindow, from: nil)
        let offset = textView.layoutManager.textOffsetAtPoint(point)
            ?? textView.selectionManager.textSelections.first?.range.location
            ?? 0
        let lineInfo = textView.layoutManager.textLineForOffset(offset)
        let lineNumber = lineInfo.map { $0.index + 1 } ?? currentCursorLine()
        let lineIndex = max(0, lineNumber - 1)
        let fileName = fileURL?.lastPathComponent ?? "Untitled"

        let fold = gutterView.foldingRibbon.model?.getCachedFoldAt(lineNumber: lineIndex)
        let isFolded = fold?.isCollapsed ?? false
        let hasFoldableBlock = fold != nil

        let menu = NSMenu(title: "Editor Context Menu")

        addSnippetAndCodingTools(to: menu, lineNumber: lineNumber)
        addCodeInspectionItems(
            to: menu,
            lineNumber: lineNumber,
            isFolded: isFolded,
            hasFoldableBlock: hasFoldableBlock
        )
        addGitAndBookmarkItems(to: menu, lineNumber: lineNumber, fileName: fileName)
        addClipboardAndAutoFillItems(to: menu)

        return menu
    }

    private func addSnippetAndCodingTools(to menu: NSMenu, lineNumber: Int) {
        let createSnippetItem = NSMenuItem(
            title: "Create Code Snippet...",
            action: #selector(contextMenuCreateSnippet(_:)),
            keyEquivalent: ""
        )
        createSnippetItem.target = self
        createSnippetItem.representedObject = lineNumber
        menu.addItem(createSnippetItem)

        menu.addItem(.separator())
        menu.addItem(createCodingToolsMenuItem())
        menu.addItem(.separator())
    }

    private func addCodeInspectionItems(
        to menu: NSMenu,
        lineNumber: Int,
        isFolded: Bool,
        hasFoldableBlock: Bool
    ) {
        menu.addItem(createRefactorMenuItem())
        menu.addItem(createFindMenuItem())
        menu.addItem(createNavigateMenuItem())

        let foldTitle = isFolded ? "Unfold" : "Fold"
        let foldItem = NSMenuItem(
            title: foldTitle,
            action: #selector(contextMenuFoldToggle(_:)),
            keyEquivalent: ""
        )
        foldItem.target = self
        foldItem.representedObject = lineNumber
        foldItem.isEnabled = hasFoldableBlock
        menu.addItem(foldItem)

        let addDocItem = NSMenuItem(
            title: "Add Documentation",
            action: #selector(contextMenuAddDocumentation(_:)),
            keyEquivalent: "/"
        )
        addDocItem.keyEquivalentModifierMask = [.command, .option]
        addDocItem.target = self
        addDocItem.representedObject = lineNumber
        addDocItem.isEnabled = isEditable
        menu.addItem(addDocItem)

        menu.addItem(.separator())
    }

    private func addGitAndBookmarkItems(to menu: NSMenu, lineNumber: Int, fileName: String) {
        let lastChangeItem = NSMenuItem(
            title: "Show Last Change for Line",
            action: #selector(contextMenuShowLastChange(_:)),
            keyEquivalent: ""
        )
        lastChangeItem.target = self
        lastChangeItem.representedObject = lineNumber
        menu.addItem(lastChangeItem)

        menu.addItem(.separator())

        let bookmarkLineItem = NSMenuItem(
            title: "Bookmark “\(fileName)” Line \(lineNumber)",
            action: #selector(contextMenuBookmarkLine(_:)),
            keyEquivalent: ""
        )
        bookmarkLineItem.target = self
        bookmarkLineItem.representedObject = lineNumber
        menu.addItem(bookmarkLineItem)

        let bookmarkFileItem = NSMenuItem(
            title: "Bookmark “\(fileName)”",
            action: #selector(contextMenuBookmarkFile(_:)),
            keyEquivalent: ""
        )
        bookmarkFileItem.target = self
        menu.addItem(bookmarkFileItem)

        menu.addItem(.separator())
    }

    private func addClipboardAndAutoFillItems(to menu: NSMenu) {
        let hasSelection = textView.selectionManager.textSelections.contains { $0.range.length > 0 }

        let cutItem = NSMenuItem(title: "Cut", action: #selector(TextView.cut(_:)), keyEquivalent: "")
        cutItem.target = textView
        cutItem.isEnabled = isEditable && hasSelection
        menu.addItem(cutItem)

        let copyItem = NSMenuItem(title: "Copy", action: #selector(TextView.copy(_:)), keyEquivalent: "")
        copyItem.target = textView
        copyItem.isEnabled = hasSelection
        menu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(TextView.paste(_:)), keyEquivalent: "")
        pasteItem.target = textView
        let hasPasteboardText = NSPasteboard.general.string(forType: .string) != nil
        pasteItem.isEnabled = isEditable && hasPasteboardText
        menu.addItem(pasteItem)

        menu.addItem(.separator())
        menu.addItem(createAutoFillMenuItem())
    }
}
