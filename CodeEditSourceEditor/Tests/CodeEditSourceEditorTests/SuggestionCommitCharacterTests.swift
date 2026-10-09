//
//  SuggestionCommitCharacterTests.swift
//  CodeEditSourceEditorTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import AppKit
import SwiftUI
import XCTest
@testable import CodeEditSourceEditor

/// Typing a commit character while a completion row is highlighted accepts that row.
final class SuggestionCommitCharacterTests: XCTestCase {
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
    private func makeCommitController(
        text: String,
        delegate: CommittingDelegate
    ) -> SuggestionViewController {
        let controller = makeController()
        controller.model?.delegate = delegate
        if let editor = controller.model?.activeTextView {
            editor.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
            editor.textView.selectionManager.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        setItems([FixtureSuggestion(label: "foo"), FixtureSuggestion(label: "foobar")], on: controller)
        return controller
    }

    private func keyDown(_ characters: String, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        // swiftlint:disable:next force_unwrapping
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 0
        )!
    }

    @MainActor
    func testCommitCharacterAfterAWordAcceptsTheHighlightedRow() {
        let delegate = CommittingDelegate(commitCharacters: ["(", "."])
        let controller = makeCommitController(text: "fo", delegate: delegate)

        let typed = controller.commitCharacter(for: keyDown("("))
        XCTAssertEqual(typed, "(")
        controller.applySelectedItem(commitCharacter: typed)

        XCTAssertEqual(delegate.applied.map(\.label), ["foo"])
        XCTAssertEqual(delegate.appliedCommitCharacters, ["("])
        controller.view.window?.orderOut(nil)
    }

    @MainActor
    func testCommitCharacterRightAfterAnAccessOperatorDoesNothing() {
        let delegate = CommittingDelegate(commitCharacters: ["(", "."])
        let controller = makeCommitController(text: "obj.", delegate: delegate)

        XCTAssertNil(controller.commitCharacter(for: keyDown("(")), "Nothing is typed yet: must not accept")
        XCTAssertNil(controller.commitCharacter(for: keyDown("a")), "Not a commit character")
        controller.view.window?.orderOut(nil)
    }

    @MainActor
    func testCommitCharacterWithACommandModifierIsIgnored() {
        let delegate = CommittingDelegate(commitCharacters: ["("])
        let controller = makeCommitController(text: "fo", delegate: delegate)

        XCTAssertNil(controller.commitCharacter(for: keyDown("(", modifiers: .command)))
        controller.view.window?.orderOut(nil)
    }

    @MainActor
    func testDelegatesWithoutCommitCharactersNeverCommit() {
        let delegate = CommittingDelegate(commitCharacters: [])
        let controller = makeController()
        controller.model?.delegate = delegate
        controller.model?.activeTextView?.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "fo")
        controller.model?.activeTextView?.textView.selectionManager.setSelectedRange(NSRange(location: 2, length: 0))
        setItems([FixtureSuggestion(label: "foo")], on: controller)

        XCTAssertNil(controller.commitCharacter(for: keyDown("(")))
        controller.view.window?.orderOut(nil)
    }

    @MainActor
    private final class CommittingDelegate: CodeSuggestionDelegate {
        let commitCharacters: Set<Character>
        private(set) var applied: [CodeSuggestionEntry] = []
        private(set) var appliedCommitCharacters: [Character?] = []

        init(commitCharacters: Set<Character>) {
            self.commitCharacters = commitCharacters
        }

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

        func completionCommitCharacters(for item: CodeSuggestionEntry) -> Set<Character> {
            commitCharacters
        }

        func completionWindowApplyCompletion(
            item: CodeSuggestionEntry,
            textView: TextViewController,
            cursorPosition: CursorPosition?,
            commitCharacter: Character?
        ) {
            applied.append(item)
            appliedCommitCharacters.append(commitCharacter)
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
