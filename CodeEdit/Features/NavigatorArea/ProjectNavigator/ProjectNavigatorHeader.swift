//
//  ProjectNavigatorHeader.swift
//  CodeEdit
//
//  Created by CodeEdit Developer on 10/10/26.
//

import SwiftUI

/// Forwards the project navigator header's actions to its outline view controller.
final class ProjectNavigatorActions: ObservableObject {
    weak var controller: ProjectNavigatorViewController?

    /// Creates an untitled file in the selected folder and starts renaming it.
    func newFile() {
        controller?.createNewFile()
    }

    /// Creates an untitled folder in the selected folder and starts renaming it.
    func newFolder() {
        controller?.createNewFolder()
    }
}

/// The strip above the project navigator's file tree, with the project name and VS Code-style
/// New File and New Folder buttons.
struct ProjectNavigatorHeader: View {
    @Environment(\.controlActiveState)
    private var activeState

    @EnvironmentObject var workspace: WorkspaceDocument

    let actions: ProjectNavigatorActions

    var body: some View {
        HStack(spacing: 2) {
            Text(workspace.workspaceFileManager?.folderUrl.lastPathComponent.uppercased() ?? "")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: actions.newFile) {
                Image(systemName: "doc.badge.plus")
            }
            .help("New File")
            .accessibilityLabel("New File")
            .accessibilityIdentifier("ProjectNavigatorNewFileButton")
            Button(action: actions.newFolder) {
                Image(systemName: "folder.badge.plus")
            }
            .help("New Folder")
            .accessibilityLabel("New Folder")
            .accessibilityIdentifier("ProjectNavigatorNewFolderButton")
        }
        .buttonStyle(.icon(font: .system(size: 13), size: 22))
        .opacity(activeState == .inactive ? 0.45 : 1)
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 26)
    }
}
