//
//  SuggestionChainTriggerTests.swift
//  CodeEditSourceEditorTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import AppKit
import XCTest
@testable import CodeEditSourceEditor

/// The chain trigger (Control-Shift-Space) reaches delegates, and delegates that know no chains cope.
final class SuggestionChainTriggerTests: XCTestCase {
    @MainActor
    private final class RecordingDelegate: CodeSuggestionDelegate {
        var triggers: [CodeSuggestionTrigger] = []

        func completionTriggerCharacters() -> Set<String> { [] }

        func completionSuggestionsRequested(
            textView: TextViewController,
            cursorPosition: CursorPosition
        ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])? {
            nil
        }

        func completionSuggestionsRequested(
            textView: TextViewController,
            cursorPosition: CursorPosition,
            trigger: CodeSuggestionTrigger
        ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])? {
            triggers.append(trigger)
            return nil
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
    }

    @MainActor
    func testTheChainTriggerIsDistinctFromTheOthers() {
        XCTAssertNotEqual(CodeSuggestionTrigger.chain, .explicit)
        XCTAssertNotEqual(CodeSuggestionTrigger.chain, .typing)
    }

    @MainActor
    func testShowingCompletionsNeedsADelegateAndACursor() {
        let editor = Mock.textViewController(theme: Mock.theme())
        editor.loadView()
        XCTAssertFalse(editor.showCodeCompletions(trigger: .chain), "No delegate: nothing to show")

        let delegate = RecordingDelegate()
        editor.completionDelegate = delegate
        editor.cursorPositions = []
        XCTAssertFalse(editor.showCodeCompletions(trigger: .chain), "No cursor: nothing to show")
    }

    @MainActor
    func testTheChainTriggerIsPassedToTheDelegate() async {
        let editor = Mock.textViewController(theme: Mock.theme())
        editor.loadView()
        // The window opens only for an editor that is on screen.
        let window = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: 640, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = editor
        window.orderFrontRegardless()
        let delegate = RecordingDelegate()
        editor.completionDelegate = delegate
        editor.cursorPositions = [CursorPosition(range: NSRange(location: 0, length: 0))]

        XCTAssertTrue(editor.showCodeCompletions(trigger: .chain))
        for _ in 0..<50 where delegate.triggers.isEmpty {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(delegate.triggers, [.chain])
        SuggestionController.shared.close()
        window.orderOut(nil)
    }
}
