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
            ("label", .label),
            ("variable.assigned", .assignedVariable),
            ("variable.global", .globalVariable),
            ("variable.parameter", .parameter),
            ("type.builtin", .primitiveType),
            ("preprocessor", .preprocessor)
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
            ("variable.member", .property),
            ("field", .property),
            ("variable.parameter.builtin", .parameter),
            ("type.builtin.c", .primitiveType),
            ("variable.assigned.member", .assignedVariable),
            ("comment.documentation", .comment)
        ]
        for (name, expected) in cases {
            XCTAssertEqual(CaptureName.fromString(name), expected, name)
        }
    }

    /// LSP semantic token type names map to their closest capture.
    func testLSPSemanticTokenNames() {
        let cases: [(String, CaptureName)] = [
            ("namespace", .namespace),
            ("module", .namespace),
            ("class", .type),
            ("macro", .macro),
            ("enumMember", .constant),
            ("typeParameter", .type)
        ]
        for (name, expected) in cases {
            XCTAssertEqual(CaptureName.fromString(name), expected, name)
        }
    }

    /// Variable tokens are narrowed by the scope and write modifiers the language server attached.
    func testRefinementByModifiers() {
        XCTAssertEqual(CaptureName.variable.refined(by: [.functionScope]), .variable)
        XCTAssertEqual(CaptureName.variable.refined(by: [.fileScope]), .globalVariable)
        XCTAssertEqual(CaptureName.variable.refined(by: [.globalScope, .readonly]), .globalVariable)
        XCTAssertEqual(CaptureName.variable.refined(by: [.classScope, .static]), .property)
        XCTAssertEqual(CaptureName.variable.refined(by: [.modification]), .assignedVariable)
        XCTAssertEqual(CaptureName.variable.refined(by: [.fileScope, .modification]), .globalVariable)
        // Only plain variables are refined.
        XCTAssertEqual(CaptureName.property.refined(by: [.modification]), .property)
        XCTAssertEqual(CaptureName.parameter.refined(by: [.modification, .functionScope]), .parameter)
        XCTAssertEqual(CaptureName.function.refined(by: [.globalScope]), .function)
        XCTAssertEqual(CaptureName.macro.refined(by: [.globalScope]), .macro)
        XCTAssertTrue(CaptureName.globalVariable.isVariableFamily)
    }

    func testScopeModifierNames() {
        XCTAssertEqual(CaptureModifier.fromString("globalScope"), .globalScope)
        XCTAssertEqual(CaptureModifier.fromString("fileScope"), .fileScope)
        XCTAssertEqual(CaptureModifier.fromString("classScope"), .classScope)
        XCTAssertEqual(CaptureModifier.fromString("functionScope"), .functionScope)
        XCTAssertEqual(CaptureModifier.fromString("static"), .static)
    }

    func testUnknownCaptures() {
        for name in ["punctuation.bracket", "text.uri", "nonexistent", "custom.unknown.capture"] {
            XCTAssertNil(CaptureName.fromString(name), name)
        }
        XCTAssertNil(CaptureName.fromString(nil))
        XCTAssertNil(CaptureName.fromString(""))
    }
}
