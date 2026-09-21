//
//  EditorJumpBarRelatedItemsButton.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/17/26.
//

import SwiftUI

/// Related Items control on the leading edge of the jump bar.
struct EditorJumpBarRelatedItemsButton: View {
    let file: CEWorkspaceFile?
    let tappedOpenFile: (CEWorkspaceFile) -> Void

    @EnvironmentObject private var editor: Editor
    @EnvironmentObject private var workspace: WorkspaceDocument

    var body: some View {
        Menu {
            recentsSection
            unsavedSection
            counterpartsSection
            openedSection
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Related Items")
        .accessibilityLabel("Related Items")
    }

    @ViewBuilder private var recentsSection: some View {
        let recents = uniqueFiles(Array(editor.history), excluding: file)
        if !recents.isEmpty {
            Section("Recents") {
                ForEach(recents, id: \.id) { item in
                    fileButton(item)
                }
            }
        }
    }

    @ViewBuilder private var unsavedSection: some View {
        let unsaved = editor.tabs.compactMap { tab -> CEWorkspaceFile? in
            guard tab.file.fileDocument?.isDocumentEdited == true else { return nil }
            return tab.file
        }
        if !unsaved.isEmpty {
            Section("Unsaved") {
                ForEach(unsaved, id: \.id) { item in
                    fileButton(item)
                }
            }
        }
    }

    @ViewBuilder private var counterpartsSection: some View {
        let counterparts = counterpartFiles()
        if !counterparts.isEmpty {
            Section("Counterparts") {
                ForEach(counterparts, id: \.id) { item in
                    fileButton(item)
                }
            }
        }
    }

    @ViewBuilder private var openedSection: some View {
        let opened = uniqueFiles(editor.tabs.map(\.file), excluding: file)
        if !opened.isEmpty {
            Section("Open Files") {
                ForEach(opened, id: \.id) { item in
                    fileButton(item)
                }
            }
        }
    }

    private func fileButton(_ item: CEWorkspaceFile) -> some View {
        Button {
            tappedOpenFile(item)
        } label: {
            HStack {
                item.icon
                Text(item.name)
            }
        }
    }

    private func uniqueFiles(_ files: [CEWorkspaceFile], excluding current: CEWorkspaceFile?) -> [CEWorkspaceFile] {
        var seen = Set<String>()
        if let current {
            seen.insert(current.id)
        }
        return files.filter { file in
            seen.insert(file.id).inserted
        }
    }

    private func counterpartFiles() -> [CEWorkspaceFile] {
        guard let file else { return [] }
        return EditorJumpBarCounterpart.counterpartURLs(for: file.url).compactMap { url in
            workspace.workspaceFileManager?.getFile(url.path, createIfNotFound: true)
        }
    }
}
