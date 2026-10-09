//
//  CompletionEditPlannerTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
@testable import CodeEdit

final class CompletionEditPlannerTests: XCTestCase {
    private func edit(_ location: Int, _ length: Int, _ text: String) -> CompletionTextEdit {
        CompletionTextEdit(range: NSRange(location: location, length: length), newText: text)
    }

    func testAdditionalEditsAreAppliedFromTheEndOfTheDocumentBackwards() {
        let plan = CompletionEditPlanner.plan(
            primary: NSRange(location: 50, length: 3),
            additional: [edit(0, 0, "a\n"), edit(20, 0, "b\n"), edit(80, 0, "c\n")]
        )
        XCTAssertEqual(plan.additional.map(\.newText), ["c\n", "b\n", "a\n"])
    }

    func testPrimaryRangeShiftsByEditsAbove() {
        let plan = CompletionEditPlanner.plan(
            primary: NSRange(location: 50, length: 3),
            additional: [edit(0, 0, "#include <vector>\n"), edit(60, 0, "tail")]
        )
        XCTAssertEqual(plan.primaryRange, NSRange(location: 50 + 18, length: 3))
    }

    func testReplacingEditShiftsByTheNetLengthChange() {
        let plan = CompletionEditPlanner.plan(
            primary: NSRange(location: 10, length: 0),
            additional: [edit(0, 4, "ab")]
        )
        XCTAssertEqual(plan.primaryRange.location, 8)
    }

    func testEditsOverlappingThePrimaryRangeAreDropped() {
        let plan = CompletionEditPlanner.plan(
            primary: NSRange(location: 10, length: 5),
            additional: [edit(12, 2, "x"), edit(8, 4, "y"), edit(0, 0, "z")]
        )
        XCTAssertEqual(plan.additional.map(\.newText), ["z"])
        XCTAssertEqual(plan.primaryRange, NSRange(location: 11, length: 5))
    }

    func testInsertionsAtTheSameOffsetKeepServerOrder() {
        let plan = CompletionEditPlanner.plan(
            primary: NSRange(location: 30, length: 0),
            additional: [edit(0, 0, "first"), edit(0, 0, "second")]
        )
        // Applied one after the other at offset 0, the later-applied text lands in front.
        XCTAssertEqual(plan.additional.map(\.newText), ["second", "first"])
    }
}
