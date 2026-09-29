//
//  Editor+StateRestoration.swift
//  CodeEdit
//
//  Created by Khan Winter on 7/3/23.
//

import Foundation
import SwiftUI
import OrderedCollections

extension EditorManager {
    /// Restores the tab manager from a captured state obtained using `saveRestorationState`
    /// - Parameter workspace: The workspace to retrieve state from.
    func restoreFromState(_ workspace: WorkspaceDocument) {
        defer {
            // No matter what, set the workspace on each editor. Even if we fail to read data.
            flattenedEditors.forEach { editor in
                editor.workspace = workspace
            }
        }

        // Observe the file manager so tabs for externally deleted files can be closed.
        workspace.workspaceFileManager?.addObserver(self)

        do {
            guard let data = workspace.getFromWorkspaceState(.openTabs) as? Data else {
                return
            }

            let state = try JSONDecoder().decode(EditorRestorationState.self, from: data)

            guard !state.groups.isEmpty else {
                logger.warning("Empty Editor State found, restoring to clean editor state.")
                initCleanState()
                return
            }

            guard let activeEditor = state.groups.find(
                editor: state.activeEditor
            ) ?? state.groups.findSomeEditor() else {
                logger.warning("Editor state could not restore active editor.")
                initCleanState()
                return
            }

            fixRestoredEditorLayout(state.groups, workspace: workspace)

            self.editorLayout = state.groups
            self.activeEditor = activeEditor
            switchToActiveEditor()
        } catch {
            logger.warning(
                "Could not restore editor state from saved data: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Fix any hanging files after restoring from saved state.
    ///
    /// After decoding the state, we're left with `CEWorkspaceFile`s that don't exist in the file manager
    /// so this function maps all those to 'real' files. Works recursively on all the tab groups.
    /// - Parameters:
    ///   - group: The tab group to fix.
    ///   - workspace: The workspace whose file manager is used to map files.
    private func fixRestoredEditorLayout(_ group: EditorLayout, workspace: WorkspaceDocument) {
        switch group {
        case let .one(data):
            fixEditor(data, workspace: workspace)
        case let .vertical(splitData):
            splitData.editorLayouts.forEach { group in
                fixRestoredEditorLayout(group, workspace: workspace)
            }
        case let .horizontal(splitData):
            splitData.editorLayouts.forEach { group in
                fixRestoredEditorLayout(group, workspace: workspace)
            }
        }
    }

    private func findEditorLayout(group: EditorLayout, searchFor id: UUID) throws -> Editor? {
        switch group {
        case let .one(data):
            return data.id == id ? data : nil
        case let .vertical(splitData):
            return try splitData.editorLayouts.compactMap { try findEditorLayout(group: $0, searchFor: id) }.first
        case let .horizontal(splitData):
            return try splitData.editorLayouts.compactMap { try findEditorLayout(group: $0, searchFor: id) }.first
        }
    }

    /// Fixes any hanging files after restoring from saved state.
    ///
    /// Resolves all file references with the workspace's file manager to ensure any referenced files use their shared
    /// object representation. Files that no longer exist on disk (for example files deleted while CodeEdit was not
    /// running) are dropped, so no stale tabs are restored for them.
    ///
    /// - Parameters:
    ///   - editor: The editor to fix.
    ///   - workspace: The workspace whose file manager is used to map files.
    private func fixEditor(_ editor: Editor, workspace: WorkspaceDocument) {
        guard let fileManager = workspace.workspaceFileManager else { return }
        let resolvedTabs = editor
            .tabs
            .filter({
                CEWorkspaceFile.fileManager.fileExists(atPath: $0.file.url.path(percentEncoded: false))
            })
            .compactMap({ fileManager.getFile($0.file.url.path(percentEncoded: false), createIfNotFound: true) })
            .map({ EditorInstance(workspace: workspace, file: $0) })

        for tab in resolvedTabs {
            do {
                try tab.file.loadCodeFile()
            } catch {
                // Don't let a single unloadable file abort restoring the remaining tabs.
                let path = tab.file.url.path()
                logger.error(
                    "Failed to load restored file \(path, privacy: .sensitive): \(error.localizedDescription)"
                )
            }
        }

        editor.workspace = workspace
        editor.tabs = OrderedSet(resolvedTabs)

        if let selectedTab = editor.selectedTab {
            let selectedPath = selectedTab.file.url.path(percentEncoded: false)
            if CEWorkspaceFile.fileManager.fileExists(atPath: selectedPath),
               let resolvedFile = fileManager.getFile(selectedPath, createIfNotFound: true) {
                editor.setSelectedTab(resolvedFile)
            } else {
                editor.setSelectedTab(editor.tabs.first?.file)
            }
        }
    }

    func saveRestorationState(_ workspace: WorkspaceDocument) {
        if let data = try? JSONEncoder().encode(
            EditorRestorationState(activeEditor: activeEditor.id, groups: editorLayout)
        ) {
            workspace.addToWorkspaceState(key: .openTabs, value: data)
        } else {
            workspace.addToWorkspaceState(key: .openTabs, value: nil)
        }
    }
}

struct EditorRestorationState: Codable {
    var activeEditor: UUID
    var groups: EditorLayout
}

extension EditorLayout: Codable {
    fileprivate enum EditorLayoutType: String, Codable {
        case one
        case vertical
        case horizontal
    }

    enum CodingKeys: String, CodingKey {
        case type
        case tabs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EditorLayoutType.self, forKey: .type)
        switch type {
        case .one:
            let editor = try container.decode(Editor.self, forKey: .tabs)
            self = .one(editor)
        case .vertical:
            let editor = try container.decode(SplitViewData.self, forKey: .tabs)
            self = .vertical(editor)
        case .horizontal:
            let editor = try container.decode(SplitViewData.self, forKey: .tabs)
            self = .horizontal(editor)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .one(data):
            try container.encode(EditorLayoutType.one, forKey: .type)
            try container.encode(data, forKey: .tabs)
        case let .vertical(data):
            try container.encode(EditorLayoutType.vertical, forKey: .type)
            try container.encode(data, forKey: .tabs)
        case let .horizontal(data):
            try container.encode(EditorLayoutType.horizontal, forKey: .type)
            try container.encode(data, forKey: .tabs)
        }
    }
}

extension SplitViewData: Codable {
    fileprivate enum SplitViewAxis: String, Codable {
        case vertical, horizontal

        init(_ swiftUI: Axis) {
            switch swiftUI {
            case .vertical: self = .vertical
            case .horizontal: self = .horizontal
            }
        }

        var swiftUI: Axis {
            switch self {
            case .vertical: return .vertical
            case .horizontal: return .horizontal
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case editorLayouts
        case axis
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let axis = try container.decode(SplitViewAxis.self, forKey: .axis).swiftUI
        let editorLayouts = try container.decode([EditorLayout].self, forKey: .editorLayouts)
        self.init(axis, editorLayouts: editorLayouts)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(editorLayouts, forKey: .editorLayouts)
        try container.encode(SplitViewAxis(axis), forKey: .axis)
    }
}

extension Editor: Codable {
    enum CodingKeys: String, CodingKey {
        case tabs
        case selectedTab
        case id
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fileURLs = try container.decode([URL].self, forKey: .tabs)
        let selectedTab = try? container.decode(URL.self, forKey: .selectedTab)
        let id = try container.decode(UUID.self, forKey: .id)
        self.init(
            files: OrderedSet(fileURLs.map { CEWorkspaceFile(url: $0) }),
            selectedTab: selectedTab == nil ? nil : EditorInstance(
                workspace: nil,
                file: CEWorkspaceFile(url: selectedTab!)
            ),
            parent: nil,
            workspace: nil
        )
        self.id = id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tabs.map { $0.file.url }, forKey: .tabs)
        try container.encode(selectedTab?.file.url, forKey: .selectedTab)
        try container.encode(id, forKey: .id)
    }
}
