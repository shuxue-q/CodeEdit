//
//  EditorJumpBarIssueNavigationTests.swift
//  CodeEditTests
//
//  Created by CodeEdit on 9/17/26.
//

import XCTest
@testable import CodeEdit

final class EditorJumpBarIssueNavigationTests: XCTestCase {
    private func diagnostic(
        _ message: String,
        severity: CMakeBuildDiagnostic.Severity,
        file: String,
        line: Int,
        column: Int = 1
    ) -> CMakeBuildDiagnostic {
        CMakeBuildDiagnostic(
            severity: severity,
            message: message,
            filePath: file,
            line: line,
            column: column
        )
    }

    func testNavigableDropsNotesAndSorts() {
        let items = [
            diagnostic("note", severity: .note, file: "/tmp/a.cpp", line: 5),
            diagnostic("later", severity: .warning, file: "/tmp/b.cpp", line: 1),
            diagnostic("earlier", severity: .error, file: "/tmp/a.cpp", line: 10),
            diagnostic("no-file", severity: .error, file: "", line: 1)
        ]
        // Empty filePath is not nil, so it is still included. Filter only nil paths.
        let navigable = WorkspaceDiagnostics.navigable(items)
        XCTAssertFalse(navigable.contains { $0.severity == .note })
        XCTAssertEqual(navigable.map(\.message), ["no-file", "earlier", "later"])
    }

    func testNextAndPreviousWalkAndWrap() {
        let first = diagnostic("first", severity: .error, file: "/tmp/a.cpp", line: 1)
        let second = diagnostic("second", severity: .warning, file: "/tmp/a.cpp", line: 10)
        let third = diagnostic("third", severity: .error, file: "/tmp/b.cpp", line: 2)
        let diagnostics = [first, second, third]

        let afterFirst = WorkspaceDiagnostics.nextIssue(
            afterFile: "/tmp/a.cpp",
            line: 1,
            column: 1,
            in: diagnostics
        )
        XCTAssertEqual(afterFirst?.message, "second")

        let afterSecond = WorkspaceDiagnostics.nextIssue(
            afterFile: "/tmp/a.cpp",
            line: 10,
            column: 1,
            in: diagnostics
        )
        XCTAssertEqual(afterSecond?.message, "third")

        let afterLast = WorkspaceDiagnostics.nextIssue(
            afterFile: "/tmp/b.cpp",
            line: 2,
            column: 1,
            in: diagnostics
        )
        XCTAssertEqual(afterLast?.message, "first")

        let beforeFirst = WorkspaceDiagnostics.previousIssue(
            beforeFile: "/tmp/a.cpp",
            line: 1,
            column: 1,
            in: diagnostics
        )
        XCTAssertEqual(beforeFirst?.message, "third")

        let beforeThird = WorkspaceDiagnostics.previousIssue(
            beforeFile: "/tmp/b.cpp",
            line: 2,
            column: 1,
            in: diagnostics
        )
        XCTAssertEqual(beforeThird?.message, "second")
    }

    func testEmptyDiagnosticsDisableNavigation() {
        XCTAssertNil(
            WorkspaceDiagnostics.nextIssue(afterFile: nil, line: 1, column: 1, in: [])
        )
        XCTAssertNil(
            WorkspaceDiagnostics.previousIssue(beforeFile: nil, line: 1, column: 1, in: [])
        )
        XCTAssertTrue(WorkspaceDiagnostics.navigable([]).isEmpty)
    }
}
