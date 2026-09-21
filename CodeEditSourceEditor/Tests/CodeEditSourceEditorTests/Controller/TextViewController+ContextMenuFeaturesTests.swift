//
//  TextViewController+ContextMenuFeaturesTests.swift
//  CodeEditSourceEditorTests
//
//  Created by CodeEdit on 2024.
//

import XCTest
@testable import CodeEditSourceEditor
import AppKit

final class ContextMenuFeaturesTests: XCTestCase {

    var controller: TextViewController!
    var theme: EditorTheme!

    override func setUpWithError() throws {
        theme = Mock.theme()
        controller = Mock.textViewController(theme: theme)
        controller.loadView()
        controller.view.frame = NSRect(x: 0, y: 0, width: 1000, height: 1000)
        controller.view.layoutSubtreeIfNeeded()
    }

    override func tearDownWithError() throws {
        controller = nil
        theme = nil
    }

    func test_docCommentGeneration() throws {
        let swiftFuncLine = "    func greet(name: String, count: Int) -> String {"
        let doc = controller.generateDocComment(for: swiftFuncLine)

        XCTAssertTrue(doc.contains("/// <#Description#>"))
        XCTAssertTrue(doc.contains("///   - name: <#name description#>"))
        XCTAssertTrue(doc.contains("///   - count: <#count description#>"))
        XCTAssertTrue(doc.contains("/// - Returns: <#return value description#>"))

        let plainLine = "    let x = 42"
        let plainDoc = controller.generateDocComment(for: plainLine)
        XCTAssertEqual(plainDoc, "    /// <#Description#>")
    }

    func test_docCommentGenerationMultiLineAndInitAndThrows() throws {
        let multiLineDecl = """
            func performRequest(
                url: URL,
                timeout: TimeInterval
            ) throws -> Response {
        """
        let doc = controller.generateDocComment(for: multiLineDecl)
        XCTAssertTrue(doc.contains("/// <#Description#>"))
        XCTAssertTrue(doc.contains("/// - Parameters:"))
        XCTAssertTrue(doc.contains("///   - url: <#url description#>"))
        XCTAssertTrue(doc.contains("///   - timeout: <#timeout description#>"))
        XCTAssertTrue(doc.contains("/// - Throws: <#description#>"))
        XCTAssertTrue(doc.contains("/// - Returns: <#return value description#>"))

        let initDecl = "    init(title: String, identifier: UUID) {"
        let initDoc = controller.generateDocComment(for: initDecl)
        XCTAssertTrue(initDoc.contains("/// <#Description#>"))
        XCTAssertTrue(initDoc.contains("/// - Parameters:"))
        XCTAssertTrue(initDoc.contains("///   - title: <#title description#>"))
        XCTAssertTrue(initDoc.contains("///   - identifier: <#identifier description#>"))

        let closureDecl = "    func load(handler: (Result<Data, Error>) -> Void) {"
        let closureDoc = controller.generateDocComment(for: closureDecl)
        XCTAssertTrue(closureDoc.contains("/// - Parameters:"))
        XCTAssertTrue(closureDoc.contains("///   - handler: <#handler description#>"))
        XCTAssertFalse(closureDoc.contains("Error>"))
    }

    func test_bookmarkManager() throws {
        let manager = EditorBookmarkManager.shared
        let initialCount = manager.bookmarks.count

        let testURL = URL(fileURLWithPath: "/tmp/TestFile.swift")
        manager.addBookmark(fileURL: testURL, fileName: "TestFile.swift", lineNumber: 10, lineContent: "let x = 1")
        XCTAssertEqual(manager.bookmarks.count, initialCount + 1)

        let added = manager.bookmarks.first { $0.fileURL == testURL && $0.lineNumber == 10 }
        XCTAssertNotNil(added)

        if let added = added {
            manager.removeBookmark(id: added.id)
            XCTAssertEqual(manager.bookmarks.count, initialCount)
        }
    }

    func test_snippetManager() throws {
        let manager = SnippetManager.shared
        let initialCount = manager.snippets.count

        let snippet = CodeSnippet(title: "MySnippet", summary: "Summary", code: "print(\"Hello\")")
        manager.addSnippet(snippet)
        XCTAssertEqual(manager.snippets.count, initialCount + 1)

        manager.removeSnippet(id: snippet.id)
        XCTAssertEqual(manager.snippets.count, initialCount)
    }

    func test_refactorSubmenuShortcutsAndSelectionState() throws {
        let dummyEvent = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!

        let menu = controller.buildContextMenu(for: dummyEvent)
        guard let refactorItem = menu.items.first(where: { $0.title == "Refactor" }),
              let submenu = refactorItem.submenu else {
            XCTFail("Missing Refactor submenu")
            return
        }

        let rename = submenu.items.first(where: { $0.title == "Rename…" })
        XCTAssertNotNil(rename)
        XCTAssertEqual(rename?.keyEquivalent, "r")
        XCTAssertEqual(rename?.keyEquivalentModifierMask, [.command, .control])

        let extractFunc = submenu.items.first(where: { $0.title == "Extract to Function" })
        XCTAssertFalse(extractFunc?.isEnabled ?? true)

        let extractVar = submenu.items.first(where: { $0.title == "Extract to Variable" })
        XCTAssertFalse(extractVar?.isEnabled ?? true)
    }

    func test_findSubmenuAllShortcuts() throws {
        let dummyEvent = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!

        let menu = controller.buildContextMenu(for: dummyEvent)
        guard let findItem = menu.items.first(where: { $0.title == "Find" }),
              let submenu = findItem.submenu else {
            XCTFail("Missing Find submenu")
            return
        }

        let useReplace = submenu.items.first(where: { $0.title == "Use Selection for Replace" })
        XCTAssertNotNil(useReplace)
        XCTAssertEqual(useReplace?.keyEquivalent, "e")
        XCTAssertEqual(useReplace?.keyEquivalentModifierMask, [.command, .option])

        let jumpSelection = submenu.items.first(where: { $0.title == "Jump to Selection" })
        XCTAssertNotNil(jumpSelection)
        XCTAssertEqual(jumpSelection?.keyEquivalent, "j")
        XCTAssertEqual(jumpSelection?.keyEquivalentModifierMask, [.command])
    }

    func test_navigateSubmenuGoBackForwardShortcuts() throws {
        let dummyEvent = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!

        let menu = controller.buildContextMenu(for: dummyEvent)
        guard let navigateItem = menu.items.first(where: { $0.title == "Navigate" }),
              let submenu = navigateItem.submenu else {
            XCTFail("Missing Navigate submenu")
            return
        }

        let goBack = submenu.items.first(where: { $0.title == "Go Back" })
        XCTAssertNotNil(goBack)
        XCTAssertEqual(goBack?.keyEquivalent, String(utf16CodeUnits: [0xF702], count: 1))
        XCTAssertEqual(goBack?.keyEquivalentModifierMask, [.command, .control])

        let goForward = submenu.items.first(where: { $0.title == "Go Forward" })
        XCTAssertNotNil(goForward)
        XCTAssertEqual(goForward?.keyEquivalent, String(utf16CodeUnits: [0xF703], count: 1))
        XCTAssertEqual(goForward?.keyEquivalentModifierMask, [.command, .control])
    }
}
