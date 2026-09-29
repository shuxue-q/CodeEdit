//
//  EditorManagerDeletedFileTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/22/25.
//

@testable import CodeEdit
import Testing
import Foundation
import OrderedCollections

@MainActor
@Suite
struct EditorManagerDeletedFileTests {
    @Test
    func closesTabWhenFileDeletedExternally() throws {
        try withTempDir { dir in
            let fileURL = dir.appending(path: "file.txt")
            try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

            let manager = EditorManager()
            let file = CEWorkspaceFile(url: fileURL)
            manager.activeEditor.openTab(file: file)
            #expect(manager.activeEditor.tabs.count == 1)

            try FileManager.default.removeItem(at: fileURL)
            manager.fileManagerUpdated(updatedItems: [])

            #expect(manager.activeEditor.tabs.isEmpty)
        }
    }

    @Test
    func keepsTabWhenFileStillExists() throws {
        try withTempDir { dir in
            let fileURL = dir.appending(path: "file.txt")
            try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

            let manager = EditorManager()
            let file = CEWorkspaceFile(url: fileURL)
            manager.activeEditor.openTab(file: file)

            manager.fileManagerUpdated(updatedItems: [])

            #expect(manager.activeEditor.tabs.count == 1)
        }
    }

    @Test
    func keepsTabWithUnsavedChangesWhenFileDeleted() throws {
        try withTempDir { dir in
            let fileURL = dir.appending(path: "file.txt")
            try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

            let manager = EditorManager()
            let file = CEWorkspaceFile(url: fileURL)
            manager.activeEditor.openTab(file: file)

            let document = try CodeFileDocument(contentsOf: fileURL, ofType: "public.source-code")
            file.fileDocument = document
            document.updateChangeCount(.changeDone)
            defer {
                document.updateChangeCount(.changeCleared)
                file.fileDocument = nil
            }

            try FileManager.default.removeItem(at: fileURL)
            manager.fileManagerUpdated(updatedItems: [])

            #expect(manager.activeEditor.tabs.count == 1)
        }
    }

    @Test
    func doesNotOpenTabForMissingFile() throws {
        try withTempDir { dir in
            let missingFile = CEWorkspaceFile(url: dir.appending(path: "missing.txt"))
            let manager = EditorManager()
            manager.activeEditor.openTab(file: missingFile)

            #expect(manager.activeEditor.tabs.isEmpty)
        }
    }

    @Test
    func dropsMissingFilesWhenRestoringState() throws {
        try withTempDir { dir in
            let existingURL = dir.appending(path: "existing.txt")
            let missingURL = dir.appending(path: "missing.txt")
            try "hello".write(to: existingURL, atomically: true, encoding: .utf8)

            let workspace = try WorkspaceDocument(for: dir, withContentsOf: dir, ofType: "")
            guard let editorManager = workspace.editorManager else {
                Issue.record("Editor manager was not set up")
                return
            }

            let editor = Editor(
                files: [CEWorkspaceFile(url: existingURL), CEWorkspaceFile(url: missingURL)],
                workspace: nil
            )
            let state = EditorRestorationState(
                activeEditor: editor.id,
                groups: .horizontal(SplitViewData(.horizontal, editorLayouts: [.one(editor)]))
            )
            workspace.addToWorkspaceState(key: .openTabs, value: try JSONEncoder().encode(state))

            editorManager.restoreFromState(workspace)

            let restoredTabs = editorManager.getFlattened().flatMap(\.tabs)
            #expect(restoredTabs.count == 1)
            #expect(restoredTabs.first?.file.name == "existing.txt")
        }
    }
}
