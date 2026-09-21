//
//  CaptureNameTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 9/14/26.
//

import XCTest
import CodeEditSourceEditor

final class CaptureNameTests: XCTestCase {
    func testExactMatches() {
        let cases: [(String, CaptureName)] = [
            ("include", .include),
            ("keyword", .keyword),
            ("type_alternate", .typeAlternate),
            ("variable.builtin", .variableBuiltin),
            ("keyword.return", .keywordReturn),
            ("keyword.function", .keywordFunction),
            ("constant", .constant),
            ("operator", .operator),
            ("label", .label)
        ]
        for (name, expected) in cases {
            XCTAssertEqual(CaptureName.fromString(name), expected, name)
        }
    }

    /// Dotted tree-sitter captures fall back to progressively shorter prefixes.
    func testPrefixFallbackMatches() {
        let cases: [(String, CaptureName)] = [
            ("function.special", .function),
            ("function.builtin", .function),
            ("constant.builtin", .constant),
            ("keyword.directive", .keyword),
            ("string.escape", .string),
            ("number.float", .number),
            ("type.qualifier", .type),
            ("variable.member", .variable),
            ("comment.documentation", .comment)
        ]
        for (name, expected) in cases {
            XCTAssertEqual(CaptureName.fromString(name), expected, name)
        }
    }

    /// LSP semantic token type names map to their closest capture.
    func testLSPSemanticTokenNames() {
        let cases: [(String, CaptureName)] = [
            ("namespace", .type),
            ("class", .type),
            ("macro", .constant),
            ("enumMember", .constant),
            ("typeParameter", .type)
        ]
        for (name, expected) in cases {
            XCTAssertEqual(CaptureName.fromString(name), expected, name)
        }
    }

    func testUnknownCaptures() {
        for name in ["punctuation.bracket", "text.uri", "nonexistent", "custom.unknown.capture"] {
            XCTAssertNil(CaptureName.fromString(name), name)
        }
        XCTAssertNil(CaptureName.fromString(nil))
        XCTAssertNil(CaptureName.fromString(""))
    }
}
