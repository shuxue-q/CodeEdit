//
//  EditorJumpBarSyntaxTests.swift
//  CodeEditTests
//
//  Created by CodeEdit on 9/28/26.
//

import XCTest
import CodeEditLanguages
import CodeEditSourceEditor
@testable import CodeEdit

final class EditorJumpBarSyntaxTests: XCTestCase {
    func testCppIndexesFunctionThenItsVariables() throws {
        let source = """
        int globalVar;

        void alpha(int param) {
          int local = param;
          local = param;
        }

        void beta() {
        }
        """
        let index = EditorJumpBarSyntaxIndex()
        index.rebuild(source: source, language: .cpp)
        XCTAssertEqual(
            index.symbols.map { "\($0.kind):\($0.name)" },
            [
                "variable:globalVar",
                "function:alpha",
                "variable:param",
                "variable:local",
                "function:beta"
            ]
        )

        let use = try XCTUnwrap(index.variable(at: cursor(in: source, occurrence: 2, of: "local")))
        XCTAssertEqual(use.name, "local")
        XCTAssertEqual(use.kind, .variable)
        let alpha = index.symbols.first { $0.name == "alpha" }
        XCTAssertEqual(use.parentID, alpha?.id)

        let onFunction = index.variable(at: cursor(in: source, occurrence: 1, of: "alpha"))
        XCTAssertNil(onFunction)
    }

    func testSwiftIndexesFunctionAboveLocal() {
        let source = """
        struct Box {
          var field: Int
          func formatCode(text: String) {
            let local = text
            _ = local
          }
        }
        """
        let index = EditorJumpBarSyntaxIndex()
        index.rebuild(source: source, language: .swift)
        let described = index.symbols.map { "\($0.kind):\($0.name)" }
        XCTAssertTrue(described.contains("function:formatCode"), described.joined(separator: ", "))
        XCTAssertTrue(described.contains("variable:field"), described.joined(separator: ", "))
        XCTAssertTrue(described.contains("variable:text"), described.joined(separator: ", "))
        XCTAssertTrue(described.contains("variable:local"), described.joined(separator: ", "))

        let use = index.variable(at: cursor(in: source, occurrence: 2, of: "local"))
        XCTAssertEqual(use?.name, "local")
        let function = index.symbols.first { $0.name == "formatCode" }
        XCTAssertEqual(use?.parentID, function?.id)
    }

    private func cursor(in source: String, occurrence: Int, of needle: String) -> CursorPosition {
        var seen = 0
        var line = 1
        var column = 1
        var index = source.startIndex
        while index < source.endIndex {
            if source[index...].hasPrefix(needle) {
                seen += 1
                if seen == occurrence {
                    return CursorPosition(line: line, column: column)
                }
            }
            if source[index] == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
            index = source.index(after: index)
        }
        return CursorPosition(line: 1, column: 1)
    }
}
