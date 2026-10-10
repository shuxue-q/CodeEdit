//
//  ProjectNavigatorViewController+NewItem.swift
//  CodeEdit
//
//  Created by CodeEdit Developer on 10/10/26.
//

import AppKit

extension ProjectNavigatorViewController {
    /// Creates an untitled file in the selected folder and starts renaming it inline.
    ///
    /// The file is written inside the workspace folder through `CEWorkspaceFileManager`, so it belongs to this
    /// project and is never recorded in the Welcome window's recents. It opens in a tab once naming finishes.
    func createNewFile() {
        createNewItem { fileManager, folder in
            try fileManager.addFile(fileName: "untitled", toFile: folder)
        }
    }

    /// Creates an untitled folder in the selected folder and starts renaming it inline.
    func createNewFolder() {
        createNewItem { fileManager, folder in
            try fileManager.addFolder(folderName: "untitled", toFile: folder)
        }
    }

    /// The folder new items go into: the selected folder, the selected file's folder, or the workspace root.
    func targetFolderForNewItem() -> CEWorkspaceFile? {
        if let selected = outlineView.item(atRow: outlineView.selectedRow) as? CEWorkspaceFile {
            return selected.isFolder ? selected : selected.parent ?? content.first
        }
        return content.first
    }

    private func createNewItem(
        _ create: (CEWorkspaceFileManager, CEWorkspaceFile) throws -> CEWorkspaceFile
    ) {
        guard let fileManager = workspace?.workspaceFileManager,
              let folder = targetFolderForNewItem() else { return }
        do {
            let newItem = try create(fileManager, folder)
            beginRenaming(newItem)
        } catch {
            let alert = NSAlert(error: error)
            alert.addButton(withTitle: "Dismiss")
            alert.runModal()
        }
    }

    /// Selects `item` and puts its row into inline rename. A file that cannot be shown (for example, hidden by
    /// the filter) opens in a tab right away instead.
    private func beginRenaming(_ item: CEWorkspaceFile) {
        expandParent(item: item.parent ?? item)
        let row = outlineView.row(forItem: item)
        guard row >= 0 else {
            if !item.isFolder {
                workspace?.editorManager?.openTab(item: item)
            }
            return
        }

        shouldSendSelectionUpdate = false
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        shouldSendSelectionUpdate = true
        outlineView.scrollRowToVisible(row)

        guard let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: true)
                as? ProjectNavigatorTableViewCell,
              let textField = cell.textField else { return }
        pendingNewFile = item.isFolder ? nil : item
        outlineView.window?.makeFirstResponder(textField)
        // Select the name without its extension, like Finder and VS Code.
        let name = textField.stringValue as NSString
        let dot = name.range(of: ".", options: .backwards)
        let length = item.isFolder || dot.location == NSNotFound || dot.location == 0 ? name.length : dot.location
        textField.currentEditor()?.selectedRange = NSRange(location: 0, length: length)
    }

    /// Opens a newly created file whose name the user left unchanged. A renamed file is opened by
    /// `moveFile(file:to:)` instead, after which the original URL no longer exists.
    func openPendingNewFileIfNeeded() {
        guard let file = pendingNewFile else { return }
        pendingNewFile = nil
        guard FileManager.default.fileExists(atPath: file.url.path) else { return }
        workspace?.listenerModel.highlightedFileItem = file
        workspace?.editorManager?.openTab(item: file)
    }
}
