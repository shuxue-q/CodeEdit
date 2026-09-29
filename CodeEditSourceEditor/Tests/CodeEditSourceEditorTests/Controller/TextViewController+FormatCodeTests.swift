//
//  TextViewController+FormatCodeTests.swift
//  CodeEditSourceEditorTests
//
//  Created by CodeEdit contributors on 9/28/26.
//

import XCTest
@testable import CodeEditSourceEditor
import AppKit

final class TextViewControllerFormatCodeTests: XCTestCase {
    private var controller: TextViewController!
    private var theme: EditorTheme!

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

    func test_formatCodeDisabledWhenDelegateDeclines() throws {
        final class Gate: SourceEditorContextMenuDelegate {
            func canFormatCode(fileURL: URL?) -> Bool { false }
        }
        let gate = Gate()
        controller.contextMenuDelegate = gate
        controller.fileURL = URL(fileURLWithPath: "/tmp/main.cpp")

        let menu = controller.buildContextMenu(for: mouseEvent())
        let item = menu.items.first { $0.title == "Format Code" }
        XCTAssertEqual(item?.isEnabled, false)
    }

    func test_formatCodeEnabledWhenDelegateAllows() throws {
        final class Gate: SourceEditorContextMenuDelegate {
            func canFormatCode(fileURL: URL?) -> Bool { true }
        }
        let gate = Gate()
        controller.contextMenuDelegate = gate
        controller.fileURL = URL(fileURLWithPath: "/tmp/main.cpp")

        let menu = controller.buildContextMenu(for: mouseEvent())
        let item = menu.items.first { $0.title == "Format Code" }
        XCTAssertEqual(item?.isEnabled, true)
        XCTAssertEqual(item?.keyEquivalent, "i")
        XCTAssertEqual(item?.keyEquivalentModifierMask, [.control])
    }

    private func mouseEvent() -> NSEvent {
        NSEvent.mouseEvent(
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
    }
}
