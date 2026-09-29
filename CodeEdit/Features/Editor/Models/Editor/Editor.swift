//
//  Editor.swift
//  CodeEdit
//
//  Created by Wouter Hennen on 16/02/2023.
//

import Foundation
import OrderedCollections
import DequeModule
import AppKit
import OSLog

final class Editor: ObservableObject, Identifiable {
    enum EditorError: Error {
        case noWorkspaceAttached
        case fileDoesNotExist
    }

    typealias Tab = EditorInstance

    /// Set of open tabs.
    @Published var tabs: OrderedSet<Tab> = [] {
        didSet {
            let change = tabs.symmetricDifference(oldValue)

            if tabs.count > oldValue.count {
                // Amount of tabs grew, so set the first new as selected.
                setSelectedTab(change.first?.file)
            } else {
                // Selected file was removed
                if let selectedTab, change.contains(selectedTab) {
                    if let oldIndex = oldValue.firstIndex(of: selectedTab), oldIndex - 1 < tabs.count, !tabs.isEmpty {
                        setSelectedTab(tabs[max(0, oldIndex-1)].file)
                    } else {
                        setSelectedTab(nil)
                    }
                }
            }
        }
    }

    /// The current offset in the history list.
    /// When set, updates the ``selectedTab`` to the tab indicated by the offset.
    /// See the ``historyOffsetDidChange()`` method for more details.
    @Published var historyOffset: Int = 0 {
        didSet {
            historyOffsetDidChange()
        }
    }

    /// Maintains the list of tabs that have been switched to.
    /// - Warning: Use the ``addToHistory(_:)`` or ``clearFuture()`` methods to modify this. Do not modify directly.
    @Published var history: Deque<CEWorkspaceFile> = []

    /// Currently selected tab.
    @Published private(set) var selectedTab: Tab?

    @Published var temporaryTab: Tab?

    var id = UUID()

    weak var parent: SplitViewData?
    weak var workspace: WorkspaceDocument?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "Editor")

    init() {
        self.tabs = []
        self.temporaryTab = nil
        self.parent = nil
        self.workspace = nil
    }

    init(
        files: OrderedSet<CEWorkspaceFile> = [],
        selectedTab: Tab? = nil,
        temporaryTab: Tab? = nil,
        parent: SplitViewData? = nil,
        workspace: WorkspaceDocument? = nil
    ) {
        self.parent = parent
        self.workspace = workspace
        // If we open the files without a valid workspace, we risk creating a file we lose track of but stays in memory
        if workspace != nil {
            files.forEach { openTab(file: $0) }
        } else {
            self.tabs = OrderedSet(files.map { EditorInstance(workspace: workspace, file: $0) })
        }
        self.selectedTab = selectedTab ?? (files.isEmpty ? nil : Tab(workspace: workspace, file: files.first!))
        self.temporaryTab = temporaryTab
    }

    init(
        files: OrderedSet<Tab> = [],
        selectedTab: Tab? = nil,
        temporaryTab: Tab? = nil,
        parent: SplitViewData? = nil,
        workspace: WorkspaceDocument? = nil
    ) {
        self.tabs = []
        self.parent = parent
        self.workspace = workspace
        files.forEach { openTab(file: $0.file) }
        self.selectedTab = selectedTab ?? tabs.first
        self.temporaryTab = temporaryTab
    }

    /// Closes the editor.
    func close() {
        parent?.closeEditor(with: id)
    }

    /// Gets the editor layout.
    func getEditorLayout() -> EditorLayout? {
        return parent?.getEditorLayout(with: id)
    }

    /// Set the selected tab. Loads the file's contents if it hasn't already been opened.
    /// - Parameter file: The file to set as the selected tab.
    func setSelectedTab(_ file: CEWorkspaceFile?) {
        guard let file else {
            selectedTab = nil
            return
        }
        guard let tab = self.tabs.first(where: { $0.file == file }) else {
            return
        }
        self.selectedTab = tab
        if tab.file.fileDocument == nil {
            do { // Ignore this error for simpler API usage.
                try openFile(item: tab)
            } catch {
                print(error)
            }
        }
    }

    /// Closes a tab in the editor.
    /// If the document has unsaved changes, the user is asked to save them first and the tab is
    /// closed once they answer (which may happen asynchronously). Adds the tab to the tab history.
    ///
    /// If the file is still open in another editor (e.g. another split), only the tab is removed:
    /// the shared document is left open and no save panel is presented.
    /// - Parameters:
    ///   - file: The tab to close
    ///   - fromHistory: If `true`, does not clear tabs ahead of the ``historyOffset``
    ///                  Used when opening tabs from the history queue where tabs ahead of the ``historyOffset`` should
    ///                  not be removed.
    func closeTab(file: CEWorkspaceFile, fromHistory: Bool = false) {
        let isOpenInOtherEditors = isFileOpenInOtherEditors(file)
        canCloseTab(file: file, askToSave: !isOpenInOtherEditors) { [weak self] shouldClose in
            guard let self, shouldClose else { return }

            if temporaryTab?.file == file {
                temporaryTab = nil
            }
            if !fromHistory {
                clearFuture()
            }
            if file != selectedTab?.file {
                addToHistory(EditorInstance(workspace: workspace, file: file))
            }
            removeTab(file)
            if let selectedTab {
                addToHistory(selectedTab)
            }
            // The document must stay alive while another editor still presents the file.
            guard !isOpenInOtherEditors else { return }
            // Reset change count to 0
            file.fileDocument?.updateChangeCount(.changeCleared)
            if let codeFile = file.fileDocument {
                codeFile.close()
            }
            // remove file from memory
            file.fileDocument = nil
        }
    }

    /// Closes the currently opened tab in the tab group.
    func closeSelectedTab() {
        guard let file = selectedTab?.file else {
            return
        }

        closeTab(file: file)
    }

    /// Opens a tab in the editor.
    /// If a tab for the item already exists, it is used instead.
    /// - Parameters:
    ///   - file: the file to open.
    ///   - asTemporary: indicates whether the tab should be opened as a temporary tab or a permanent tab.
    func openTab(file: CEWorkspaceFile, asTemporary: Bool) {
        guard file.doesExist else {
            logger.debug("Not opening tab for file that no longer exists: \(file.url.path(), privacy: .sensitive)")
            return
        }
        let item = EditorInstance(workspace: workspace, file: file)
        // Item is already opened in a tab.
        guard !tabs.contains(item) || !asTemporary else {
            selectedTab = item
            addToHistory(item)
            return
        }

        switch (temporaryTab, asTemporary) {
        case (.some(let tab), true):
            replaceTemporaryTab(tab: tab, with: item)
        case (.some(let tab), false) where tab == item:
            temporaryTab = nil
        case (.some(let tab), false) where tab != item:
            openTab(file: item.file)
        case (.some, false):
            // A temporary tab exists, but we don't want to open this one as temporary.
            // Clear the temp tab and open the new one.
            openTab(file: item.file)
        case (.none, true):
            openTab(file: item.file)
            temporaryTab = item
        case (.none, false):
            openTab(file: item.file)
        }
    }

    /// Replaces the given temporary tab with a new tab item.
    /// - Parameters:
    ///   - tab: The temporary tab to replace.
    ///   - newItem: The new tab to replace it with and open as a temporary tab.
    private func replaceTemporaryTab(tab: Tab, with newItem: Tab) {
        if let index = tabs.firstIndex(of: tab) {
            do {
                try openFile(item: newItem)
            } catch {
                logger.error("Error opening file: \(error)")
            }

            clearFuture()
            addToHistory(newItem)
            tabs.remove(tab)
            tabs.insert(newItem, at: index)
            self.selectedTab = newItem
            temporaryTab = newItem
        } else {
            // If we couldn't find the current temporary tab (invalid state) we should still do *something*
            openTab(file: newItem.file)
            temporaryTab = newItem
        }
    }

    /// Opens a tab in the editor.
    /// - Parameters:
    ///   - file: The tab to open.
    ///   - index: Index where the tab needs to be added. If nil, it is added to the back.
    ///   - fromHistory: Indicates whether the tab has been opened from going back in history.
    func openTab(file: CEWorkspaceFile, at index: Int? = nil, fromHistory: Bool = false) {
        guard file.doesExist else {
            logger.debug("Not opening tab for file that no longer exists: \(file.url.path(), privacy: .sensitive)")
            return
        }
        let item = Tab(workspace: workspace, file: file)
        if let index {
            tabs.insert(item, at: index)
        } else {
            if let selectedTab, let currentIndex = tabs.firstIndex(of: selectedTab) {
                tabs.insert(item, at: tabs.index(after: currentIndex))
            } else {
                tabs.append(item)
            }
        }

        selectedTab = item
        if !fromHistory {
            clearFuture()
            addToHistory(item)
        }
        do {
            try openFile(item: item)
        } catch {
            logger.error("Error opening file: \(error)")
        }
    }

    private func openFile(item: Tab) throws {
        // If this isn't attached to a workspace, loading a new NSDocument will cause a loose document we can't close
        guard item.file.fileDocument == nil else {
            return
        }

        guard workspace != nil else {
            throw EditorError.noWorkspaceAttached
        }

        guard item.file.doesExist else {
            throw EditorError.fileDoesNotExist
        }

        try item.file.loadCodeFile()
    }

    /// Checks whether the file is presented by a tab of any other editor of the workspace.
    /// - Parameter file: The file to look for.
    /// - Returns: `true` if another editor (e.g. another split) has the file open.
    private func isFileOpenInOtherEditors(_ file: CEWorkspaceFile) -> Bool {
        guard let editorManager = workspace?.editorManager else { return false }
        return editorManager.getFlattened().contains { editor in
            editor.id != id && editor.tabs.contains(where: { $0.file == file })
        }
    }

    /// Check if tab can be closed.
    ///
    /// An edited document presents a dialog to save or discard changes before the tab closes.
    /// - Parameters:
    ///   - file: The file to check.
    ///   - askToSave: If `false`, no save dialog is presented for an edited document.
    ///   - completion: Invoked with `true` if the tab can be closed, `false` if the user canceled.
    ///                 Invoked asynchronously when a dialog is presented.
    private func canCloseTab(
        file: CEWorkspaceFile,
        askToSave: Bool = true,
        completion: @escaping (Bool) -> Void
    ) {
        guard askToSave, let codeFile = file.fileDocument, codeFile.isDocumentEdited else {
            completion(true)
            return
        }

        codeFile.confirmUnsavedClose(
            in: workspace?.windowControllers.first?.window,
            completion: completion
        )
    }

    /// Remove the given file from tabs.
    /// - Parameter file: The file to remove.
    func removeTab(_ file: CEWorkspaceFile) {
        tabs.removeAll(where: { tab in tab.file == file })
        if temporaryTab?.file == file {
            temporaryTab = nil
        }
    }
}

extension Editor: Equatable, Hashable {
    static func == (lhs: Editor, rhs: Editor) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
