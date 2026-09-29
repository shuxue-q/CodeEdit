//
//  SuggestionCompletionTests.swift
//  CodeEditSourceEditorTests
//
//  Created by CodeEdit Contributors on 9/27/26.
//

import AppKit
import SwiftUI
import XCTest
@testable import CodeEditSourceEditor

final class SuggestionCompletionTests: XCTestCase {
    private var retainedModel: SuggestionViewModel?
    func testHeaderIsReadFromDocumentation() {
        XCTAssertEqual(SuggestionOrigin.header(in: "From `<type_traits>`"), "<type_traits>")
        XCTAssertEqual(SuggestionOrigin.header(in: "From <filesystem>"), "<filesystem>")
        XCTAssertNil(SuggestionOrigin.header(in: "No header here"))
    }

    func testPreviewKeepsADistinctDetailWhenDocumentationMatches() {
        let traits = FixtureSuggestion(
            label: "std::add_const",
            detail: "struct add_const",
            documentation: "From `<type_traits>`"
        )
        let pointer = FixtureSuggestion(
            label: "std::add_pointer",
            detail: "struct add_pointer",
            documentation: "From `<type_traits>`"
        )
        XCTAssertEqual(
            SuggestionPreviewContent.text(for: traits),
            "struct add_const\n\nFrom `<type_traits>`"
        )
        XCTAssertNotEqual(
            SuggestionPreviewContent.text(for: traits),
            SuggestionPreviewContent.text(for: pointer)
        )
    }

    @MainActor
    func testArrowSelectionUpdatesThePreviewIncludingTheFirstItem() {
        let controller = makeController()
        setItems([
            FixtureSuggestion(label: "CLI::adl_detail", documentation: "From `<CLI/CLI.hpp>`"),
            FixtureSuggestion(label: "std::add_const", documentation: "From `<type_traits>`"),
            FixtureSuggestion(label: "std::add_pointer", documentation: "From `<memory>`")
        ], on: controller)

        XCTAssertEqual(controller.tableView.selectedRow, 0)
        XCTAssertEqual(controller.previewView.documentation, "From `<CLI/CLI.hpp>`")

        controller.moveSelection(by: 1)
        XCTAssertEqual(controller.tableView.selectedRow, 1)
        XCTAssertEqual(controller.previewView.documentation, "From `<type_traits>`")

        controller.moveSelection(by: 1)
        XCTAssertEqual(controller.previewView.documentation, "From `<memory>`")

        controller.moveSelection(by: -2)
        XCTAssertEqual(controller.tableView.selectedRow, 0)
        XCTAssertEqual(controller.previewView.documentation, "From `<CLI/CLI.hpp>`")
        controller.view.window?.orderOut(nil)
    }

    @MainActor
    func testResolveFillsTheFirstItemsPreviewWithoutResettingSelection() {
        let delegate = ResolvingDelegate()
        let controller = makeController()
        controller.model?.delegate = delegate
        let resolved = expectation(description: "first item resolved")
        delegate.onResolve = { resolved.fulfill() }

        setItems([
            FixtureSuggestion(label: "CLI::adl_detail", documentation: nil),
            FixtureSuggestion(label: "std::add_const", documentation: "From `<type_traits>`")
        ], on: controller)

        wait(for: [resolved], timeout: 2)
        let applied = expectation(description: "resolved preview applied")
        DispatchQueue.main.async {
            DispatchQueue.main.async { applied.fulfill() }
        }
        wait(for: [applied], timeout: 2)

        XCTAssertEqual(controller.tableView.selectedRow, 0)
        XCTAssertEqual(controller.previewView.documentation, "Resolved CLI::adl_detail")

        let second = expectation(description: "second item resolved")
        delegate.onResolve = { second.fulfill() }
        controller.moveSelection(by: 1)
        wait(for: [second], timeout: 2)
        let secondApplied = expectation(description: "second preview applied")
        DispatchQueue.main.async {
            DispatchQueue.main.async { secondApplied.fulfill() }
        }
        wait(for: [secondApplied], timeout: 2)
        XCTAssertEqual(controller.tableView.selectedRow, 1)
        XCTAssertEqual(controller.previewView.documentation, "Resolved std::add_const")
        controller.view.window?.orderOut(nil)
    }

    @MainActor
    func testInlineCompletionInfoShowsTheHeaderUnderTheList() {
        let controller = makeController()
        guard let editor = controller.model?.activeTextView else {
            return XCTFail("Missing editor")
        }
        var configuration = editor.configuration
        configuration.peripherals.showInlineCompletionInfo = true
        configuration.peripherals.visibleCompletionCount = 5
        editor.configuration = configuration

        setItems([
            FixtureSuggestion(
                label: "std::filesystem::perm_options",
                detail: "std::filesystem::perm_options",
                documentation: "From `<filesystem>`"
            ),
            FixtureSuggestion(
                label: "std::add_const",
                detail: "struct add_const",
                documentation: "From `<type_traits>`"
            )
        ], on: controller)

        XCTAssertTrue(controller.previewView.isHidden)
        XCTAssertEqual(controller.previewWidthConstraint?.constant ?? -1, 0, accuracy: 0.1)
        XCTAssertTrue(controller.originLabel.attributedStringValue.string.contains("<filesystem>"))
        XCTAssertFalse(controller.footerView.isHidden)

        controller.moveSelection(by: 1)
        XCTAssertTrue(controller.originLabel.attributedStringValue.string.contains("<type_traits>"))
        XCTAssertEqual(controller.tableView.selectedRow, 1)

        let rowHeight = controller.tableView.rowHeight
        let listHeight = rowHeight * 2 + SuggestionController.WINDOW_PADDING * 2
        XCTAssertGreaterThan(controller.preferredContentSize.height, listHeight)
        controller.view.window?.orderOut(nil)
    }

    @MainActor
    func testVisibleCompletionCountLimitsTheWindow() {
        let controller = makeController()
        guard let editor = controller.model?.activeTextView else {
            return XCTFail("Missing editor")
        }
        var configuration = editor.configuration
        configuration.peripherals.visibleCompletionCount = 3
        editor.configuration = configuration

        setItems((0..<8).map { FixtureSuggestion(label: "item\($0)", documentation: nil) }, on: controller)

        let rowHeight = controller.tableView.rowHeight
        let listHeight = rowHeight * 3 + SuggestionController.WINDOW_PADDING * 2
        XCTAssertEqual(controller.preferredContentSize.height, listHeight, accuracy: 1)
        XCTAssertEqual(controller.tableView.numberOfRows, 8)
        controller.view.window?.orderOut(nil)
    }

    @MainActor
    private func makeController() -> SuggestionViewController {
        let model = SuggestionViewModel()
        retainedModel = model
        let controller = SuggestionViewController()
        controller.model = model
        let editor = Mock.textViewController(theme: Mock.theme())
        editor.loadView()
        model.activeTextView = editor

        let window = SuggestionController.makeWindow()
        window.contentViewController = controller
        window.setFrame(NSRect(x: 80, y: 80, width: 640, height: 320), display: true)
        window.orderFrontRegardless()
        return controller
    }

    @MainActor
    private func setItems(_ items: [CodeSuggestionEntry], on controller: SuggestionViewController) {
        controller.model?.items = items
        let laidOut = expectation(description: "items laid out")
        DispatchQueue.main.async {
            controller.view.layoutSubtreeIfNeeded()
            laidOut.fulfill()
        }
        wait(for: [laidOut], timeout: 2)
    }

    @MainActor
    private final class ResolvingDelegate: CodeSuggestionDelegate {
        var onResolve: (() -> Void)?

        func completionSuggestionsRequested(
            textView: TextViewController,
            cursorPosition: CursorPosition
        ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])? {
            nil
        }

        func completionOnCursorMove(
            textView: TextViewController,
            cursorPosition: CursorPosition
        ) -> [CodeSuggestionEntry]? {
            nil
        }

        func completionWindowApplyCompletion(
            item: CodeSuggestionEntry,
            textView: TextViewController,
            cursorPosition: CursorPosition?
        ) { }

        func completionWindowResolve(item: CodeSuggestionEntry) async -> CodeSuggestionEntry? {
            onResolve?()
            return FixtureSuggestion(label: item.label, documentation: "Resolved \(item.label)")
        }
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
}
