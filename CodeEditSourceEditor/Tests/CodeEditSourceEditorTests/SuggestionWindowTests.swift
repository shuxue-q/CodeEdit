//
//  SuggestionWindowTests.swift
//  CodeEditSourceEditorTests
//
//  Created by CodeEdit Contributors on 9/27/26.
//

import AppKit
import SwiftUI
import XCTest
@testable import CodeEditSourceEditor

final class SuggestionWindowTests: XCTestCase {
    func testWindowUsesTheTallerPanel() {
        let listOnly = measurement(itemCount: 6, previewHeight: 30, screenLimit: 800)
        XCTAssertEqual(listOnly, 22 * 6 + 10, accuracy: 0.1)

        let documentation = measurement(itemCount: 6, previewHeight: 280, screenLimit: 800)
        XCTAssertEqual(documentation, 280, accuracy: 0.1)
    }

    func testWindowKeepsEveryVisibleRowWhenDocumentationIsShort() {
        let height = measurement(itemCount: 8, previewHeight: 40, screenLimit: 800)
        XCTAssertGreaterThan(height, 22 * 2)
        XCTAssertEqual(height, 22 * 8 + 10, accuracy: 0.1)
    }

    func testLongDocumentationCapsToTheScreenWithoutShrinkingTheList() {
        let height = measurement(itemCount: 6, previewHeight: 2_000, screenLimit: 500)
        XCTAssertEqual(height, 500, accuracy: 0.1)
    }

    private func measurement(
        itemCount: Int,
        previewHeight: CGFloat,
        screenLimit: CGFloat,
        maxVisibleRows: CGFloat = 8.5
    ) -> CGFloat {
        SuggestionWindowMeasurement(
            rowHeight: 22,
            itemCount: itemCount,
            maxVisibleRows: maxVisibleRows,
            verticalPadding: 5,
            previewHeight: previewHeight,
            screenLimit: screenLimit
        ).contentHeight
    }

    func testVisibleRowCountCapsTheList() {
        let height = measurement(itemCount: 20, previewHeight: 0, screenLimit: 800, maxVisibleRows: 5)
        XCTAssertEqual(height, 22 * 5 + 10, accuracy: 0.1)
    }

    func testInlineCodeIsHighlightedAndBackticksRemoved() {
        let blocks = SuggestionDocumentationFormatter.blocks(
            markdown: "From `<CLI/CLI.hpp>`\nThrown when validation fails",
            font: .systemFont(ofSize: 12),
            theme: nil
        )
        XCTAssertEqual(blocks.count, 1)
        guard case .prose(let prose) = blocks[0] else {
            return XCTFail("Expected prose")
        }
        XCTAssertFalse(prose.string.contains("`"))
        XCTAssertTrue(prose.string.contains("CLI/CLI.hpp"))
        XCTAssertTrue(prose.string.contains("Thrown when validation fails"))
        XCTAssertTrue(monoRun(in: prose, containing: "CLI/CLI.hpp"))
    }

    func testCodeFenceIsHighlightedSeparatelyFromTheDescription() {
        let markdown = """
        ```cpp
        class CLI::InvalidError
        ```
        Thrown when validation fails
        """
        let blocks = SuggestionDocumentationFormatter.blocks(
            markdown: markdown,
            font: .systemFont(ofSize: 12),
            theme: nil
        )
        XCTAssertEqual(blocks.count, 2)
        guard case .code(let code) = blocks[0] else {
            return XCTFail("Expected a code block")
        }
        XCTAssertTrue(code.string.contains("class"))
        XCTAssertTrue(code.string.contains("InvalidError"))
        XCTAssertFalse(code.string.contains("```"))
        guard case .prose(let prose) = blocks[1] else {
            return XCTFail("Expected prose after the code block")
        }
        XCTAssertTrue(prose.string.contains("Thrown when validation fails"))
        XCTAssertNotEqual(
            color(of: "class", in: code),
            color(of: "InvalidError", in: code)
        )
    }

    func testHeadingMarkersAreNotShown() {
        let blocks = SuggestionDocumentationFormatter.blocks(
            markdown: "### InvalidError\nThrown when validation fails",
            font: .systemFont(ofSize: 12),
            theme: nil
        )
        guard case .prose(let prose) = blocks.first else {
            return XCTFail("Expected prose")
        }
        XCTAssertFalse(prose.string.contains("#"))
        XCTAssertTrue(prose.string.contains("InvalidError"))
    }

    @MainActor
    func testArrowSelectionKeepsEveryRowVisible() {
        let model = SuggestionViewModel()
        let controller = SuggestionViewController()
        controller.model = model
        let editor = Mock.textViewController(theme: Mock.theme())
        editor.loadView()
        var configuration = editor.configuration
        configuration.peripherals.visibleCompletionCount = 9
        editor.configuration = configuration
        model.activeTextView = editor

        let window = SuggestionController.makeWindow()
        window.contentViewController = controller
        window.setFrame(NSRect(x: 80, y: 80, width: 640, height: 320), display: true)
        window.orderFrontRegardless()

        model.items = (0..<9).map { index in
            FixtureSuggestion(
                label: "std::add_\(index)",
                documentation: index == 1 ? "From `<type_traits>`" : nil
            )
        }

        let laidOut = expectation(description: "items laid out")
        DispatchQueue.main.async {
            controller.view.layoutSubtreeIfNeeded()
            laidOut.fulfill()
        }
        wait(for: [laidOut], timeout: 2)

        let initialHeight = window.frame.height
        selectRow(1, on: controller)
        let downHeight = window.frame.height
        let downRows = rowHeights(controller.tableView)
        selectRow(0, on: controller)
        let upHeight = window.frame.height

        XCTAssertGreaterThan(initialHeight, 120)
        XCTAssertEqual(downHeight, initialHeight, accuracy: 1)
        XCTAssertEqual(upHeight, initialHeight, accuracy: 1)
        XCTAssertEqual(downRows.count, 9)
        XCTAssertTrue(downRows.allSatisfy { $0 > 12 })
        window.orderOut(nil)
    }

    @MainActor
    private func selectRow(_ row: Int, on controller: SuggestionViewController) {
        let laidOut = expectation(description: "row \(row) laid out")
        controller.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        DispatchQueue.main.async {
            controller.view.layoutSubtreeIfNeeded()
            controller.view.window?.displayIfNeeded()
            laidOut.fulfill()
        }
        wait(for: [laidOut], timeout: 2)
    }

    private func rowHeights(_ tableView: NSTableView) -> [CGFloat] {
        (0..<tableView.numberOfRows).map { tableView.rect(ofRow: $0).height }
    }

    func testPreviewContentGrowsWithDocumentationAndStaysAtTheTop() {
        let preview = CodeSuggestionPreviewView(frame: NSRect(x: 0, y: 0, width: 320, height: 220))
        preview.documentation = "From `<CLI/CLI.hpp>`"
        let shortHeight = preview.contentHeight(forWidth: 320)

        preview.documentation = String(repeating: "Thrown when validation fails. ", count: 40)
        let tallHeight = preview.contentHeight(forWidth: 320)
        XCTAssertGreaterThan(tallHeight, shortHeight)
        XCTAssertGreaterThan(shortHeight, 20)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = preview
        preview.layoutSubtreeIfNeeded()

        let scrollView = preview.subviews.compactMap { $0 as? NSScrollView }.first
        let stack = scrollView?.documentView?.subviews.first
        XCTAssertNotNil(stack)
        guard let scrollView, let stack else { return }
        let stackInClip = scrollView.contentView.convert(stack.bounds, from: stack)
        XCTAssertGreaterThan(stack.bounds.height, 8)
        XCTAssertLessThan(stackInClip.minY, 12)
    }

    private struct FixtureSuggestion: CodeSuggestionEntry {
        var label: String
        var detail: String?
        var documentation: String?
        var pathComponents: [String]?
        var targetPosition: CursorPosition?
        var sourcePreview: String?
        var image: Image { Image(systemName: "cube") }
        var imageColor: Color { .orange }
        var deprecated: Bool { false }
    }

    private func monoRun(in string: NSAttributedString, containing needle: String) -> Bool {
        var found = false
        string.enumerateAttribute(.font, in: NSRange(location: 0, length: string.length)) { value, range, _ in
            let text = (string.string as NSString).substring(with: range)
            guard text.contains(needle), let font = value as? NSFont else { return }
            let traits = font.fontDescriptor.symbolicTraits
            found = traits.contains(.monoSpace) || font.fontName.lowercased().contains("mono")
        }
        return found
    }

    private func color(of needle: String, in string: NSAttributedString) -> NSColor? {
        var color: NSColor?
        let fullRange = NSRange(location: 0, length: string.length)
        string.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            let text = (string.string as NSString).substring(with: range)
            if text == needle {
                color = value as? NSColor
            }
        }
        return color
    }
}
