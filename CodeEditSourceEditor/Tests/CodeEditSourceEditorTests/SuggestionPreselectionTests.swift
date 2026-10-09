//
//  SuggestionPreselectionTests.swift
//  CodeEditSourceEditorTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import AppKit
import SwiftUI
import XCTest
@testable import CodeEditSourceEditor

/// The window selects and bolds the row the delegate preselects.
final class SuggestionPreselectionTests: XCTestCase {
    private var retainedModel: SuggestionViewModel?

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
    private func show(
        _ labels: [String],
        preselectedIndex: Int?,
        on controller: SuggestionViewController
    ) {
        controller.model?.preselectedIndex = preselectedIndex
        controller.model?.items = labels.map { Fixture(label: $0) }
        let laidOut = expectation(description: "items laid out")
        DispatchQueue.main.async {
            controller.view.layoutSubtreeIfNeeded()
            laidOut.fulfill()
        }
        wait(for: [laidOut], timeout: 2)
    }

    @MainActor
    private func isBold(row: Int, in controller: SuggestionViewController) -> Bool? {
        let host = controller.tableView.view(atColumn: 0, row: row, makeIfNecessary: true)
            as? NSHostingView<CodeSuggestionLabelView>
        return host?.rootView.isPreselected
    }

    @MainActor
    func testPreselectedRowIsSelectedAndBold() {
        let controller = makeController()
        show(["alpha", "beta", "gamma"], preselectedIndex: 2, on: controller)

        XCTAssertEqual(controller.tableView.selectedRow, 2)
        XCTAssertEqual(isBold(row: 2, in: controller), true)
        XCTAssertEqual(isBold(row: 0, in: controller), false)
        controller.view.window?.orderOut(nil)
    }

    @MainActor
    func testWithoutPreselectionTheFirstRowIsHighlightedButNotBold() {
        let controller = makeController()
        show(["alpha", "beta"], preselectedIndex: nil, on: controller)

        XCTAssertEqual(controller.tableView.selectedRow, 0)
        XCTAssertEqual(isBold(row: 0, in: controller), false)
        controller.view.window?.orderOut(nil)
    }

    @MainActor
    func testAnOutOfRangePreselectionFallsBackToTheFirstRow() {
        let controller = makeController()
        show(["alpha", "beta"], preselectedIndex: 9, on: controller)

        XCTAssertEqual(controller.tableView.selectedRow, 0)
        controller.view.window?.orderOut(nil)
    }

    @MainActor
    func testDelegatesThatOnlyImplementTheOldMethodsPreselectNothing() async {
        let delegate = LegacyDelegate()
        let editor = Mock.textViewController(theme: Mock.theme())
        editor.loadView()
        let position = CursorPosition(range: NSRange(location: 0, length: 0))

        let result = await delegate.completionSuggestionsResult(
            textView: editor, cursorPosition: position, trigger: .explicit
        )
        XCTAssertEqual(result?.items.map(\.label), ["legacy"])
        XCTAssertNil(result?.preselectedIndex)

        let update = delegate.completionSuggestionsUpdated(textView: editor, cursorPosition: position)
        XCTAssertEqual(update?.items.map(\.label), ["legacy"])
        XCTAssertNil(update?.preselectedIndex)
    }

    @MainActor
    private final class LegacyDelegate: CodeSuggestionDelegate {
        func completionSuggestionsRequested(
            textView: TextViewController,
            cursorPosition: CursorPosition
        ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])? {
            (cursorPosition, [Fixture(label: "legacy")])
        }

        func completionOnCursorMove(
            textView: TextViewController,
            cursorPosition: CursorPosition
        ) -> [CodeSuggestionEntry]? {
            [Fixture(label: "legacy")]
        }

        func completionWindowApplyCompletion(
            item: CodeSuggestionEntry,
            textView: TextViewController,
            cursorPosition: CursorPosition?
        ) { }
    }

    private struct Fixture: CodeSuggestionEntry {
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
