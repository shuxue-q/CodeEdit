//
//  TextViewController+SnippetTests.swift
//  CodeEditSourceEditorTests
//
//  Created by CodeEdit Contributors on 9/29/26.
//

import XCTest
@testable import CodeEditSourceEditor

final class SnippetParserTests: XCTestCase {
    func test_placeholdersBecomeTextWithTabStops() {
        let parsed = SnippetParser.parse("begin(${1:initializer_list<Ep> il})")
        XCTAssertEqual(parsed.text, "begin(initializer_list<Ep> il)")
        XCTAssertEqual(parsed.tabStops, [SnippetTabStop(index: 1, range: NSRange(location: 6, length: 23))])
        // No $0: the final stop is the end of the text.
        XCTAssertEqual(parsed.navigationGroups.last, [NSRange(location: 30, length: 0)])
    }

    func test_navigationOrderIsNumericThenFinal() {
        let parsed = SnippetParser.parse("for (${1:int i = 0}; ${2:i < n}; ${3:++i}) {\n\t$0\n}")
        XCTAssertEqual(parsed.text, "for (int i = 0; i < n; ++i) {\n\t\n}")
        XCTAssertEqual(parsed.navigationGroups, [
            [NSRange(location: 5, length: 9)],
            [NSRange(location: 16, length: 5)],
            [NSRange(location: 23, length: 3)],
            [NSRange(location: 31, length: 0)]
        ])
    }

    func test_nestedChoicesVariablesAndEscapes() {
        let parsed = SnippetParser.parse(#"${1:a${2:b}c} ${3|x,y|} ${TM_FILENAME:file} \$1 \} $ $x"#)
        XCTAssertEqual(parsed.text, "abc x file $1 } $ ")
        XCTAssertEqual(parsed.navigationGroups.dropLast(), [
            [NSRange(location: 0, length: 3)],
            [NSRange(location: 1, length: 1)],
            [NSRange(location: 4, length: 1)]
        ])
    }

    func test_malformedSyntaxStaysText() {
        XCTAssertEqual(SnippetParser.plainText("${1:unclosed"), "${1:unclosed")
        XCTAssertEqual(SnippetParser.plainText("cost: $"), "cost: $")
    }

    func test_offsetsAreUTF16() {
        let parsed = SnippetParser.parse("😀(${1:é})")
        XCTAssertEqual(parsed.tabStops.first?.range, NSRange(location: 3, length: 1))
    }
}

final class SnippetSessionTests: XCTestCase {
    private func session(_ snippet: String, at location: Int = 10) -> SnippetSession {
        SnippetSession(snippet: SnippetParser.parse(snippet), location: location)!
    }

    func test_noPlaceholdersMeansNoSession() {
        XCTAssertNil(SnippetSession(snippet: SnippetParser.parse("foo()$0"), location: 0))
    }

    func test_typingOverActivePlaceholderResizesItAndShiftsLaterStops() {
        var session = session("f(${1:aaa}, ${2:bb})") // at 10: "f(aaa, bb)"
        XCTAssertEqual(session.activeRanges, [NSRange(location: 12, length: 3)])
        // Replace the selected "aaa" with "x", then type "y" at its end.
        XCTAssertTrue(session.applyEdit(replacing: NSRange(location: 12, length: 3), length: 1))
        XCTAssertTrue(session.applyEdit(replacing: NSRange(location: 13, length: 0), length: 1))
        XCTAssertEqual(session.activeRanges, [NSRange(location: 12, length: 2)])
        XCTAssertTrue(session.move(backwards: false))
        XCTAssertEqual(session.activeRanges, [NSRange(location: 16, length: 2)])
        XCTAssertEqual(session.extent, NSRange(location: 10, length: 9))
    }

    func test_editsBeforeTheSnippetShiftIt() {
        var session = session("f(${1:a})")
        XCTAssertTrue(session.applyEdit(replacing: NSRange(location: 0, length: 0), length: 4))
        XCTAssertEqual(session.activeRanges, [NSRange(location: 16, length: 1)])
    }

    func test_editAcrossTheSnippetBoundaryEndsIt() {
        var session = session("f(${1:a})")
        XCTAssertFalse(session.applyEdit(replacing: NSRange(location: 8, length: 4), length: 0))
    }

    func test_movingPastTheLastPlaceholderReachesTheFinalStop() {
        var session = session("f(${1:a}, ${2:b})")
        XCTAssertFalse(session.move(backwards: true))
        XCTAssertTrue(session.move(backwards: false))
        XCTAssertTrue(session.move(backwards: false))
        XCTAssertTrue(session.isAtFinalStop)
        XCTAssertEqual(session.activeRanges, [NSRange(location: 17, length: 0)])
    }
}

final class TextViewControllerSnippetTests: XCTestCase {
    var controller: TextViewController!

    override func setUpWithError() throws {
        controller = Mock.textViewController(theme: Mock.theme())
        controller.loadView()
        controller.view.frame = NSRect(x: 0, y: 0, width: 1000, height: 1000)
        controller.view.layoutSubtreeIfNeeded()
    }

    private var selectedRanges: [NSRange] {
        controller.textView.selectionManager.textSelections.map(\.range)
    }

    func test_insertSnippetSelectsPlaceholdersAndTabEndsAfterTheCall() {
        controller.setText("std::be")
        controller.insertSnippet("begin(${1:first}, ${2:last})", replacing: NSRange(location: 5, length: 2))
        XCTAssertEqual(controller.text, "std::begin(first, last)")
        XCTAssertTrue(controller.isSnippetSessionActive)
        XCTAssertEqual(selectedRanges, [NSRange(location: 11, length: 5)])

        controller.textView.replaceCharacters(in: NSRange(location: 11, length: 5), with: "v")
        XCTAssertEqual(controller.text, "std::begin(v, last)")

        controller.moveToSnippetTabStop()
        XCTAssertEqual(selectedRanges, [NSRange(location: 14, length: 4)])

        controller.moveToSnippetTabStop(backwards: true)
        XCTAssertEqual(selectedRanges, [NSRange(location: 11, length: 1)])

        controller.moveToSnippetTabStop()
        controller.moveToSnippetTabStop()
        XCTAssertEqual(selectedRanges, [NSRange(location: 19, length: 0)])
        XCTAssertFalse(controller.isSnippetSessionActive)
    }

    func test_tabKeyMovesBetweenPlaceholdersInsteadOfIndenting() throws {
        controller.setText("")
        controller.insertSnippet("f(${1:a}, ${2:b})", replacing: NSRange(location: 0, length: 0))
        let tab = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 0x30
        ))
        XCTAssertNil(controller.handleEvent(event: tab))
        XCTAssertEqual(controller.text, "f(a, b)")
        XCTAssertEqual(selectedRanges, [NSRange(location: 5, length: 1)])
    }

    func test_snippetWithoutPlaceholdersPutsCursorAtFinalStop() {
        controller.setText("")
        controller.insertSnippet("include <$0>", replacing: NSRange(location: 0, length: 0))
        XCTAssertEqual(controller.text, "include <>")
        XCTAssertFalse(controller.isSnippetSessionActive)
        XCTAssertEqual(selectedRanges, [NSRange(location: 9, length: 0)])
    }

    func test_selectionLeavingTheSnippetEndsTheSession() {
        controller.setText("x = ")
        controller.insertSnippet("f(${1:a})", replacing: NSRange(location: 4, length: 0))
        controller.textView.selectionManager.setSelectedRange(NSRange(location: 0, length: 0))
        controller.updateSnippetSessionForSelectionChange()
        XCTAssertFalse(controller.isSnippetSessionActive)
    }
}
