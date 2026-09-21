//
//  TextViewController+ContextMenuTests.swift
//  CodeEditSourceEditorTests
//
//  Created by CodeEdit on 2024.
//

import XCTest
@testable import CodeEditSourceEditor
import AppKit

final class TextViewControllerContextMenuTests: XCTestCase {

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

    func test_contextMenuStructure() throws {
        controller.fileURL = URL(fileURLWithPath: "/tmp/MyFile.swift")
        controller.text = "func calculateSum(a: Int, b: Int) -> Int {\n    return a + b\n}\n"

        let dummyEvent = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: NSPoint(x: 10, y: 990),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!

        let menu = controller.buildContextMenu(for: dummyEvent)
        XCTAssertNotNil(menu)

        let itemTitles = menu.items.map { $0.isSeparatorItem ? "---" : $0.title }

        XCTAssertTrue(itemTitles.contains("Create Code Snippet..."))
        XCTAssertTrue(itemTitles.contains("Show Coding Tools"))
        XCTAssertTrue(itemTitles.contains("Refactor"))
        XCTAssertTrue(itemTitles.contains("Find"))
        XCTAssertTrue(itemTitles.contains("Navigate"))
        XCTAssertTrue(itemTitles.contains { $0 == "Fold" || $0 == "Unfold" })
        XCTAssertTrue(itemTitles.contains("Add Documentation"))
        XCTAssertTrue(itemTitles.contains("Show Last Change for Line"))
        XCTAssertTrue(itemTitles.contains { $0.hasPrefix("Bookmark “MyFile.swift” Line") })
        XCTAssertTrue(itemTitles.contains("Bookmark “MyFile.swift”"))
        XCTAssertTrue(itemTitles.contains("Cut"))
        XCTAssertTrue(itemTitles.contains("Copy"))
        XCTAssertTrue(itemTitles.contains("Paste"))
        XCTAssertTrue(itemTitles.contains("AutoFill"))
    }

    func test_codingToolsSubmenu() throws {
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
        guard let codingToolsItem = menu.items.first(where: { $0.title == "Show Coding Tools" }),
              let submenu = codingToolsItem.submenu else {
            XCTFail("Missing Show Coding Tools submenu")
            return
        }

        let subTitles = submenu.items.map { $0.isSeparatorItem ? "---" : $0.title }
        XCTAssertEqual(subTitles, [
            "Show Coding Tools…",
            "---",
            "Proofread",
            "Rewrite",
            "Summary",
            "Explain Code",
            "Generate Tests"
        ])
    }

    func test_refactorSubmenu() throws {
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

        let titles = submenu.items.filter { !$0.isSeparatorItem }.map { $0.title }
        XCTAssertTrue(titles.contains("Rename…"))
        XCTAssertTrue(titles.contains("Extract to Function"))
        XCTAssertTrue(titles.contains("Extract to Variable"))
        XCTAssertTrue(titles.contains("Add Missing Switch Cases"))
        XCTAssertTrue(titles.contains("Generate Memberwise Initializer"))
        XCTAssertTrue(titles.contains("Format Document"))
    }

    func test_findSubmenu() throws {
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

        let titles = submenu.items.filter { !$0.isSeparatorItem }.map { $0.title }
        XCTAssertTrue(titles.contains("Find in Workspace…"))
        XCTAssertTrue(titles.contains("Find Selected Text in Workspace"))
        XCTAssertTrue(titles.contains("Find Selected Symbol in Workspace"))
        XCTAssertTrue(titles.contains("Find Call Hierarchy"))
        XCTAssertTrue(titles.contains("Find in File…"))
        XCTAssertTrue(titles.contains("Find and Replace…"))
        XCTAssertTrue(titles.contains("Find Next"))
        XCTAssertTrue(titles.contains("Find Previous"))
        XCTAssertTrue(titles.contains("Use Selection for Find"))
    }

    func test_navigateSubmenu() throws {
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

        let titles = submenu.items.filter { !$0.isSeparatorItem }.map { $0.title }
        XCTAssertTrue(titles.contains("Jump to Definition"))
        XCTAssertTrue(titles.contains("Jump to Type Definition"))
        XCTAssertTrue(titles.contains("Reveal in Project Navigator"))
        XCTAssertTrue(titles.contains("Jump to Next Counterpart"))
        XCTAssertTrue(titles.contains("Jump to Previous Counterpart"))
        XCTAssertTrue(titles.contains("Show Previous Tab"))
        XCTAssertTrue(titles.contains("Show Next Tab"))
        XCTAssertTrue(titles.contains("Go Back"))
        XCTAssertTrue(titles.contains("Go Forward"))
    }

    func test_autoFillSubmenu() throws {
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
        guard let autoFillItem = menu.items.first(where: { $0.title == "AutoFill" }),
              let submenu = autoFillItem.submenu else {
            XCTFail("Missing AutoFill submenu")
            return
        }

        let titles = submenu.items.map { $0.title }
        XCTAssertTrue(titles.contains("Passwords…"))
        XCTAssertTrue(titles.contains("Contact…"))
    }

    func test_addDocumentationKeyboardShortcut() throws {
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
        let docItem = menu.items.first(where: { $0.title == "Add Documentation" })
        XCTAssertNotNil(docItem)
        XCTAssertEqual(docItem?.keyEquivalent, "/")
        XCTAssertEqual(docItem?.keyEquivalentModifierMask, [.command, .option])
    }

    func test_contextMenuClipboardKeyEquivalentsEmpty() throws {
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
        let cutItem = menu.items.first(where: { $0.title == "Cut" })
        let copyItem = menu.items.first(where: { $0.title == "Copy" })
        let pasteItem = menu.items.first(where: { $0.title == "Paste" })

        XCTAssertEqual(cutItem?.keyEquivalent, "")
        XCTAssertEqual(copyItem?.keyEquivalent, "")
        XCTAssertEqual(pasteItem?.keyEquivalent, "")
    }

    func test_autoFillSubmenuHasValidIcon() throws {
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
        let autoFillItem = menu.items.first(where: { $0.title == "AutoFill" })
        XCTAssertNotNil(autoFillItem)
        XCTAssertNotNil(autoFillItem?.image)
    }
}
