//
//  ProjectNavigatorNewItemTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Developer on 10/10/26.
//

import AppKit
import Testing
import Foundation
import WelcomeWindow
@testable import CodeEdit

/// The project navigator header's New File / New Folder buttons create items inside the workspace,
/// rename them inline, and never add them to the Welcome window's recents.
@Suite(.serialized)
@MainActor
struct ProjectNavigatorNewItemTests {
    /// A workspace with `src/main.cpp`, shown by a navigator controller hosted in a window.
    private struct Fixture {
        let root: URL
        let workspace: WorkspaceDocument
        let controller: ProjectNavigatorViewController
        let window: NSWindow
        /// Held here because the file manager keeps observers weakly.
        let reloader: OutlineReloader

        func close() {
            workspace.editorManager?.activeEditor.tabs.forEach { $0.file.fileDocument?.close() }
            CodeEditDocumentController.shared.removeDocument(workspace)
            window.close()
        }

        /// Selects the navigator row for `url`.
        func select(_ url: URL) throws {
            let file = try #require(workspace.workspaceFileManager?.getFile(url.path, createIfNotFound: true))
            controller.expandParent(item: file.parent ?? file)
            let row = controller.outlineView.row(forItem: file)
            try #require(row >= 0)
            controller.outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        /// The text field being edited inline, if any.
        var editingTextField: NSTextField? {
            (window.firstResponder as? NSTextView)?.delegate as? NSTextField
        }

        /// Types `name` into the inline rename field and commits it.
        func finishRenaming(as name: String? = nil) throws {
            let textField = try #require(editingTextField)
            if let name {
                textField.stringValue = name
            }
            window.makeFirstResponder(controller.outlineView)
        }

        var tabPaths: [String] {
            workspace.editorManager?.activeEditor.tabs.map(\.file.url.path) ?? []
        }
    }

    private func makeFixture(defaults: UserDefaults) throws -> Fixture {
        RecentsStore.defaults = defaults
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "ProjectNavigatorNewItemTests_\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temp.appending(path: "src"), withIntermediateDirectories: true)
        let root = URL(
            filePath: try #require(temp.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath),
            directoryHint: .isDirectory
        )
        try "int main() {}\n".write(to: root.appending(path: "src/main.cpp"), atomically: true, encoding: .utf8)

        let workspace = WorkspaceDocument()
        try workspace.read(from: root, ofType: "")
        CodeEditDocumentController.shared.addDocument(workspace)

        let controller = ProjectNavigatorViewController()
        controller.workspace = workspace
        controller.editor = workspace.editorManager?.activeEditor
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        let reloader = OutlineReloader(controller: controller)
        workspace.workspaceFileManager?.addObserver(reloader)
        return Fixture(root: root, workspace: workspace, controller: controller, window: window, reloader: reloader)
    }

    private func withFixture(_ test: (Fixture) throws -> Void) throws {
        let defaultsName = "ProjectNavigatorNewItemTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let fixture = try makeFixture(defaults: defaults)
        defer {
            fixture.close()
            try? FileManager.default.removeItem(at: fixture.root)
        }
        try test(fixture)
        #expect(RecentsStore.recentProjectURLs().isEmpty)
    }

    @Test
    func newFileIsCreatedInSelectedFolderAndOpensAfterRenaming() throws {
        try withFixture { fixture in
            let src = fixture.root.appending(path: "src")
            try fixture.select(src.appending(path: "main.cpp"))
            let tabsBefore = fixture.tabPaths
            fixture.controller.createNewFile()

            // The extension is inferred from sibling files, so only the base name is fixed.
            let created = try FileManager.default.contentsOfDirectory(atPath: src.path)
                .filter { $0.hasPrefix("untitled") }
            let untitled = src.appending(path: try #require(created.first))
            #expect(created.count == 1)
            let textField = try #require(fixture.editingTextField)
            #expect(textField.currentEditor()?.selectedRange == NSRange(location: 0, length: "untitled".count))
            #expect(fixture.tabPaths == tabsBefore)

            try fixture.finishRenaming(as: "hello.cpp")

            let renamed = src.appending(path: "hello.cpp")
            #expect(FileManager.default.fileExists(atPath: renamed.path))
            #expect(!FileManager.default.fileExists(atPath: untitled.path))
            #expect(fixture.tabPaths.last == renamed.path)
            #expect(!fixture.tabPaths.contains(untitled.path))
        }
    }

    @Test
    func newFileKeepingItsNameStillOpens() throws {
        try withFixture { fixture in
            fixture.controller.outlineView.deselectAll(nil)
            fixture.controller.createNewFile()

            let untitled = fixture.root.appending(path: "untitled")
            #expect(FileManager.default.fileExists(atPath: untitled.path))
            try fixture.finishRenaming()

            #expect(fixture.tabPaths == [untitled.path])
        }
    }

    @Test
    func newFolderIsCreatedInSelectedFolder() throws {
        try withFixture { fixture in
            try fixture.select(fixture.root.appending(path: "src"))
            fixture.controller.createNewFolder()

            var isDirectory: ObjCBool = false
            let folder = fixture.root.appending(path: "src/untitled")
            #expect(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
            try fixture.finishRenaming(as: "lib")

            #expect(FileManager.default.fileExists(atPath: fixture.root.appending(path: "src/lib").path))
            #expect(fixture.tabPaths.isEmpty)
        }
    }
}

/// Reloads the navigator when files change, as `ProjectNavigatorOutlineView.Coordinator` does in the app.
private final class OutlineReloader: CEWorkspaceFileManagerObserver {
    weak var controller: ProjectNavigatorViewController?

    init(controller: ProjectNavigatorViewController) {
        self.controller = controller
    }

    func fileManagerUpdated(updatedItems: Set<CEWorkspaceFile>) {
        for item in updatedItems {
            controller?.outlineView.reloadItem(item, reloadChildren: true)
        }
    }
}
