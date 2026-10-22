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
        let item = NSMenuItem(
            title: String(localized: "Show Coding Tools", bundle: .module),
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu(title: String(localized: "Show Coding Tools", bundle: .module))

        let tools: [(String, Selector)] = [
            (String(localized: "Show Coding Tools…", bundle: .module), #selector(contextMenuShowCodingTools(_:))),
            (String(localized: "Proofread", bundle: .module), #selector(contextMenuCodingToolProofread(_:))),
            (String(localized: "Rewrite", bundle: .module), #selector(contextMenuCodingToolRewrite(_:))),
            (String(localized: "Summary", bundle: .module), #selector(contextMenuCodingToolSummary(_:))),
            (String(localized: "Explain Code", bundle: .module), #selector(contextMenuCodingToolExplain(_:))),
            (String(localized: "Generate Tests", bundle: .module), #selector(contextMenuCodingToolTests(_:)))
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
        let item = NSMenuItem(title: String(localized: "Refactor", bundle: .module), action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: String(localized: "Refactor", bundle: .module))
        let hasSelection = textView.selectionManager.textSelections.contains { $0.range.length > 0 }

        addRefactorExtractItems(to: submenu, hasSelection: hasSelection)
        submenu.addItem(.separator())
        addRefactorGenerationItems(to: submenu)

        item.submenu = submenu
        return item
    }

    private func addRefactorExtractItems(to menu: NSMenu, hasSelection: Bool) {
        let rename = NSMenuItem(
            title: String(localized: "Rename…", bundle: .module),
            action: #selector(contextMenuRefactorRename(_:)),
            keyEquivalent: "r"
        )
        rename.keyEquivalentModifierMask = [.command, .control]
        rename.target = self
        rename.isEnabled = isEditable
        menu.addItem(rename)

        let extractFunc = NSMenuItem(
            title: String(localized: "Extract to Function", bundle: .module),
            action: #selector(contextMenuRefactorExtractFunction(_:)),
            keyEquivalent: ""
        )
        extractFunc.target = self
        extractFunc.isEnabled = isEditable && hasSelection
        menu.addItem(extractFunc)

        let extractVar = NSMenuItem(
            title: String(localized: "Extract to Variable", bundle: .module),
            action: #selector(contextMenuRefactorExtractVariable(_:)),
            keyEquivalent: ""
        )
        extractVar.target = self
        extractVar.isEnabled = isEditable && hasSelection
        menu.addItem(extractVar)
    }

    private func addRefactorGenerationItems(to menu: NSMenu) {
        let switchCases = NSMenuItem(
            title: String(localized: "Add Missing Switch Cases", bundle: .module),
            action: #selector(contextMenuRefactorAddMissingSwitchCases(_:)),
            keyEquivalent: ""
        )
        switchCases.target = self
        switchCases.isEnabled = isEditable
        menu.addItem(switchCases)

        let memberwiseInit = NSMenuItem(
            title: String(localized: "Generate Memberwise Initializer", bundle: .module),
            action: #selector(contextMenuRefactorGenerateMemberwiseInit(_:)),
            keyEquivalent: ""
        )
        memberwiseInit.target = self
        memberwiseInit.isEnabled = isEditable
        menu.addItem(memberwiseInit)
    }

    func createFindMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "Find", bundle: .module), action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: String(localized: "Find", bundle: .module))

        let findWorkspace = NSMenuItem(
            title: String(localized: "Find in Workspace…", bundle: .module),
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
            (
                String(localized: "Find Selected Text in Workspace", bundle: .module),
                #selector(contextMenuFindSelectedTextInWorkspace(_:))
            ),
            (
                String(localized: "Find Selected Symbol in Workspace", bundle: .module),
                #selector(contextMenuFindSelectedSymbolInWorkspace(_:))
            ),
            (String(localized: "Find Call Hierarchy", bundle: .module), #selector(contextMenuFindCallHierarchy(_:)))
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
            title: String(localized: "Find in File…", bundle: .module),
            action: #selector(contextMenuFindInFile(_:)),
            keyEquivalent: "f"
        )
        findInFile.keyEquivalentModifierMask = [.command]
        findInFile.target = self
        menu.addItem(findInFile)

        let findReplace = NSMenuItem(
            title: String(localized: "Find and Replace…", bundle: .module),
            action: #selector(contextMenuFindAndReplace(_:)),
            keyEquivalent: "f"
        )
        findReplace.keyEquivalentModifierMask = [.command, .option]
        findReplace.target = self
        menu.addItem(findReplace)

        let findNext = NSMenuItem(
            title: String(localized: "Find Next", bundle: .module),
            action: #selector(contextMenuFindNext(_:)),
            keyEquivalent: "g"
        )
        findNext.keyEquivalentModifierMask = [.command]
        findNext.target = self
        menu.addItem(findNext)

        let findPrev = NSMenuItem(
            title: String(localized: "Find Previous", bundle: .module),
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
            title: String(localized: "Use Selection for Find", bundle: .module),
            action: #selector(contextMenuUseSelectionForFind(_:)),
            keyEquivalent: "e"
        )
        useSelection.keyEquivalentModifierMask = [.command]
        useSelection.target = self
        menu.addItem(useSelection)

        let useSelectionReplace = NSMenuItem(
            title: String(localized: "Use Selection for Replace", bundle: .module),
            action: #selector(contextMenuUseSelectionForReplace(_:)),
            keyEquivalent: "e"
        )
        useSelectionReplace.keyEquivalentModifierMask = [.command, .option]
        useSelectionReplace.target = self
        menu.addItem(useSelectionReplace)

        let jumpToSelection = NSMenuItem(
            title: String(localized: "Jump to Selection", bundle: .module),
            action: #selector(contextMenuJumpToSelection(_:)),
            keyEquivalent: "j"
        )
        jumpToSelection.keyEquivalentModifierMask = [.command]
        jumpToSelection.target = self
        menu.addItem(jumpToSelection)
    }

    func createNavigateMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "Navigate", bundle: .module), action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: String(localized: "Navigate", bundle: .module))

        addJumpSubItems(to: submenu)
        addCounterpartSubItems(to: submenu)
        addTabAndHistorySubItems(to: submenu)

        item.submenu = submenu
        return item
    }

    private func addJumpSubItems(to menu: NSMenu) {
        let jumpToDef = NSMenuItem(
            title: String(localized: "Jump to Definition", bundle: .module),
            action: #selector(contextMenuJumpToDefinition(_:)),
            keyEquivalent: "j"
        )
        jumpToDef.keyEquivalentModifierMask = [.command, .control]
        jumpToDef.target = self
        menu.addItem(jumpToDef)

        let jumpToType = NSMenuItem(
            title: String(localized: "Jump to Type Definition", bundle: .module),
            action: #selector(contextMenuJumpToTypeDefinition(_:)),
            keyEquivalent: ""
        )
        jumpToType.target = self
        menu.addItem(jumpToType)

        let reveal = NSMenuItem(
            title: String(localized: "Reveal in Project Navigator", bundle: .module),
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
            title: String(localized: "Jump to Next Counterpart", bundle: .module),
            action: #selector(contextMenuJumpToNextCounterpart(_:)),
            keyEquivalent: String(utf16CodeUnits: [0xF700], count: 1)
        )
        next.keyEquivalentModifierMask = [.command, .control]
        next.target = self
        menu.addItem(next)

        let prev = NSMenuItem(
            title: String(localized: "Jump to Previous Counterpart", bundle: .module),
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
            title: String(localized: "Show Previous Tab", bundle: .module),
            action: #selector(contextMenuShowPreviousTab(_:)),
            keyEquivalent: "{"
        )
        prevTab.keyEquivalentModifierMask = [.command]
        prevTab.target = self
        menu.addItem(prevTab)

        let nextTab = NSMenuItem(
            title: String(localized: "Show Next Tab", bundle: .module),
            action: #selector(contextMenuShowNextTab(_:)),
            keyEquivalent: "}"
        )
        nextTab.keyEquivalentModifierMask = [.command]
        nextTab.target = self
        menu.addItem(nextTab)

        menu.addItem(.separator())

        let goBack = NSMenuItem(
            title: String(localized: "Go Back", bundle: .module),
            action: #selector(contextMenuGoBack(_:)),
            keyEquivalent: String(utf16CodeUnits: [0xF702], count: 1)
        )
        goBack.keyEquivalentModifierMask = [.command, .control]
        goBack.target = self
        menu.addItem(goBack)

        let goForward = NSMenuItem(
            title: String(localized: "Go Forward", bundle: .module),
            action: #selector(contextMenuGoForward(_:)),
            keyEquivalent: String(utf16CodeUnits: [0xF703], count: 1)
        )
        goForward.keyEquivalentModifierMask = [.command, .control]
        goForward.target = self
        menu.addItem(goForward)
    }

    func createAutoFillMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "AutoFill", bundle: .module), action: nil, keyEquivalent: "")
        if let symbolImage = NSImage(
            systemSymbolName: "rectangle.and.pencil.and.ellipsis",
            accessibilityDescription: String(localized: "AutoFill", bundle: .module)
        ) {
            item.image = symbolImage
        }
        let submenu = NSMenu(title: String(localized: "AutoFill", bundle: .module))

        let passwords = NSMenuItem(
            title: String(localized: "Passwords…", bundle: .module),
            action: #selector(contextMenuAutoFillPasswords(_:)),
            keyEquivalent: ""
        )
        passwords.target = self
        submenu.addItem(passwords)

        let contacts = NSMenuItem(
            title: String(localized: "Contact…", bundle: .module),
            action: #selector(contextMenuAutoFillContacts(_:)),
            keyEquivalent: ""
        )
        contacts.target = self
        submenu.addItem(contacts)

        item.submenu = submenu
        return item
    }
}
