//
//  TextViewController+ContextMenuSubmenus.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit on 2024.
//

import AppKit

extension TextViewController {

    // MARK: - Submenu Builders

    func createCodingToolsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Show Coding Tools", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Show Coding Tools")

        let tools: [(String, Selector)] = [
            ("Show Coding Tools…", #selector(contextMenuShowCodingTools(_:))),
            ("Proofread", #selector(contextMenuCodingToolProofread(_:))),
            ("Rewrite", #selector(contextMenuCodingToolRewrite(_:))),
            ("Summary", #selector(contextMenuCodingToolSummary(_:))),
            ("Explain Code", #selector(contextMenuCodingToolExplain(_:))),
            ("Generate Tests", #selector(contextMenuCodingToolTests(_:)))
        ]

        for (index, tool) in tools.enumerated() {
            if index == 1 { submenu.addItem(.separator()) }
            let menuItem = NSMenuItem(title: tool.0, action: tool.1, keyEquivalent: "")
            menuItem.target = self
            submenu.addItem(menuItem)
        }

        item.submenu = submenu
        return item
    }

    func createRefactorMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Refactor", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Refactor")
        let hasSelection = textView.selectionManager.textSelections.contains { $0.range.length > 0 }

        addRefactorExtractItems(to: submenu, hasSelection: hasSelection)
        submenu.addItem(.separator())
        addRefactorGenerationItems(to: submenu)

        item.submenu = submenu
        return item
    }

    private func addRefactorExtractItems(to menu: NSMenu, hasSelection: Bool) {
        let rename = NSMenuItem(
            title: "Rename…",
            action: #selector(contextMenuRefactorRename(_:)),
            keyEquivalent: "r"
        )
        rename.keyEquivalentModifierMask = [.command, .control]
        rename.target = self
        rename.isEnabled = isEditable
        menu.addItem(rename)

        let extractFunc = NSMenuItem(
            title: "Extract to Function",
            action: #selector(contextMenuRefactorExtractFunction(_:)),
            keyEquivalent: ""
        )
        extractFunc.target = self
        extractFunc.isEnabled = isEditable && hasSelection
        menu.addItem(extractFunc)

        let extractVar = NSMenuItem(
            title: "Extract to Variable",
            action: #selector(contextMenuRefactorExtractVariable(_:)),
            keyEquivalent: ""
        )
        extractVar.target = self
        extractVar.isEnabled = isEditable && hasSelection
        menu.addItem(extractVar)
    }

    private func addRefactorGenerationItems(to menu: NSMenu) {
        let switchCases = NSMenuItem(
            title: "Add Missing Switch Cases",
            action: #selector(contextMenuRefactorAddMissingSwitchCases(_:)),
            keyEquivalent: ""
        )
        switchCases.target = self
        switchCases.isEnabled = isEditable
        menu.addItem(switchCases)

        let memberwiseInit = NSMenuItem(
            title: "Generate Memberwise Initializer",
            action: #selector(contextMenuRefactorGenerateMemberwiseInit(_:)),
            keyEquivalent: ""
        )
        memberwiseInit.target = self
        memberwiseInit.isEnabled = isEditable
        menu.addItem(memberwiseInit)
    }

    func createFindMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Find")

        let findWorkspace = NSMenuItem(
            title: "Find in Workspace…",
            action: #selector(contextMenuFindInWorkspace(_:)),
            keyEquivalent: "F"
        )
        findWorkspace.keyEquivalentModifierMask = [.command, .shift]
        findWorkspace.target = self
        submenu.addItem(findWorkspace)

        addFindWorkspaceSubItems(to: submenu)
        addFindFileSubItems(to: submenu)

        item.submenu = submenu
        return item
    }

    private func addFindWorkspaceSubItems(to menu: NSMenu) {
        let items: [(String, Selector)] = [
            ("Find Selected Text in Workspace", #selector(contextMenuFindSelectedTextInWorkspace(_:))),
            ("Find Selected Symbol in Workspace", #selector(contextMenuFindSelectedSymbolInWorkspace(_:))),
            ("Find Call Hierarchy", #selector(contextMenuFindCallHierarchy(_:)))
        ]
        for item in items {
            let menuItem = NSMenuItem(title: item.0, action: item.1, keyEquivalent: "")
            menuItem.target = self
            menu.addItem(menuItem)
        }
        menu.addItem(.separator())
    }

    private func addFindFileSubItems(to menu: NSMenu) {
        let findInFile = NSMenuItem(
            title: "Find in File…",
            action: #selector(contextMenuFindInFile(_:)),
            keyEquivalent: "f"
        )
        findInFile.keyEquivalentModifierMask = [.command]
        findInFile.target = self
        menu.addItem(findInFile)

        let findReplace = NSMenuItem(
            title: "Find and Replace…",
            action: #selector(contextMenuFindAndReplace(_:)),
            keyEquivalent: "f"
        )
        findReplace.keyEquivalentModifierMask = [.command, .option]
        findReplace.target = self
        menu.addItem(findReplace)

        let findNext = NSMenuItem(
            title: "Find Next",
            action: #selector(contextMenuFindNext(_:)),
            keyEquivalent: "g"
        )
        findNext.keyEquivalentModifierMask = [.command]
        findNext.target = self
        menu.addItem(findNext)

        let findPrev = NSMenuItem(
            title: "Find Previous",
            action: #selector(contextMenuFindPrevious(_:)),
            keyEquivalent: "g"
        )
        findPrev.keyEquivalentModifierMask = [.command, .shift]
        findPrev.target = self
        menu.addItem(findPrev)

        menu.addItem(.separator())
        addFindSelectionSubItems(to: menu)
    }

    private func addFindSelectionSubItems(to menu: NSMenu) {
        let useSelection = NSMenuItem(
            title: "Use Selection for Find",
            action: #selector(contextMenuUseSelectionForFind(_:)),
            keyEquivalent: "e"
        )
        useSelection.keyEquivalentModifierMask = [.command]
        useSelection.target = self
        menu.addItem(useSelection)

        let useSelectionReplace = NSMenuItem(
            title: "Use Selection for Replace",
            action: #selector(contextMenuUseSelectionForReplace(_:)),
            keyEquivalent: "e"
        )
        useSelectionReplace.keyEquivalentModifierMask = [.command, .option]
        useSelectionReplace.target = self
        menu.addItem(useSelectionReplace)

        let jumpToSelection = NSMenuItem(
            title: "Jump to Selection",
            action: #selector(contextMenuJumpToSelection(_:)),
            keyEquivalent: "j"
        )
        jumpToSelection.keyEquivalentModifierMask = [.command]
        jumpToSelection.target = self
        menu.addItem(jumpToSelection)
    }

    func createNavigateMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Navigate", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Navigate")

        addJumpSubItems(to: submenu)
        addCounterpartSubItems(to: submenu)
        addTabAndHistorySubItems(to: submenu)

        item.submenu = submenu
        return item
    }

    private func addJumpSubItems(to menu: NSMenu) {
        let jumpToDef = NSMenuItem(
            title: "Jump to Definition",
            action: #selector(contextMenuJumpToDefinition(_:)),
            keyEquivalent: "j"
        )
        jumpToDef.keyEquivalentModifierMask = [.command, .control]
        jumpToDef.target = self
        menu.addItem(jumpToDef)

        let jumpToType = NSMenuItem(
            title: "Jump to Type Definition",
            action: #selector(contextMenuJumpToTypeDefinition(_:)),
            keyEquivalent: ""
        )
        jumpToType.target = self
        menu.addItem(jumpToType)

        let reveal = NSMenuItem(
            title: "Reveal in Project Navigator",
            action: #selector(contextMenuRevealInProjectNavigator(_:)),
            keyEquivalent: "j"
        )
        reveal.keyEquivalentModifierMask = [.command, .shift]
        reveal.target = self
        menu.addItem(reveal)

        menu.addItem(.separator())
    }

    private func addCounterpartSubItems(to menu: NSMenu) {
        let next = NSMenuItem(
            title: "Jump to Next Counterpart",
            action: #selector(contextMenuJumpToNextCounterpart(_:)),
            keyEquivalent: String(utf16CodeUnits: [0xF700], count: 1)
        )
        next.keyEquivalentModifierMask = [.command, .control]
        next.target = self
        menu.addItem(next)

        let prev = NSMenuItem(
            title: "Jump to Previous Counterpart",
            action: #selector(contextMenuJumpToPreviousCounterpart(_:)),
            keyEquivalent: String(utf16CodeUnits: [0xF701], count: 1)
        )
        prev.keyEquivalentModifierMask = [.command, .control]
        prev.target = self
        menu.addItem(prev)

        menu.addItem(.separator())
    }

    private func addTabAndHistorySubItems(to menu: NSMenu) {
        let prevTab = NSMenuItem(
            title: "Show Previous Tab",
            action: #selector(contextMenuShowPreviousTab(_:)),
            keyEquivalent: "{"
        )
        prevTab.keyEquivalentModifierMask = [.command]
        prevTab.target = self
        menu.addItem(prevTab)

        let nextTab = NSMenuItem(
            title: "Show Next Tab",
            action: #selector(contextMenuShowNextTab(_:)),
            keyEquivalent: "}"
        )
        nextTab.keyEquivalentModifierMask = [.command]
        nextTab.target = self
        menu.addItem(nextTab)

        menu.addItem(.separator())

        let goBack = NSMenuItem(
            title: "Go Back",
            action: #selector(contextMenuGoBack(_:)),
            keyEquivalent: String(utf16CodeUnits: [0xF702], count: 1)
        )
        goBack.keyEquivalentModifierMask = [.command, .control]
        goBack.target = self
        menu.addItem(goBack)

        let goForward = NSMenuItem(
            title: "Go Forward",
            action: #selector(contextMenuGoForward(_:)),
            keyEquivalent: String(utf16CodeUnits: [0xF703], count: 1)
        )
        goForward.keyEquivalentModifierMask = [.command, .control]
        goForward.target = self
        menu.addItem(goForward)
    }

    func createAutoFillMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "AutoFill", action: nil, keyEquivalent: "")
        if let symbolImage = NSImage(
            systemSymbolName: "rectangle.and.pencil.and.ellipsis",
            accessibilityDescription: "AutoFill"
        ) {
            item.image = symbolImage
        }
        let submenu = NSMenu(title: "AutoFill")

        let passwords = NSMenuItem(
            title: "Passwords…",
            action: #selector(contextMenuAutoFillPasswords(_:)),
            keyEquivalent: ""
        )
        passwords.target = self
        submenu.addItem(passwords)

        let contacts = NSMenuItem(
            title: "Contact…",
            action: #selector(contextMenuAutoFillContacts(_:)),
            keyEquivalent: ""
        )
        contacts.target = self
        submenu.addItem(contacts)

        item.submenu = submenu
        return item
    }
}
