//
//  SyntacticContextResolverTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import XCTest
@testable import CodeEdit

final class SyntacticContextResolverTests: XCTestCase {
    private func resolver(nodeTypes: [String]) -> SyntacticContextResolver {
        SyntacticContextResolver { _ in nodeTypes }
    }

    func testCommentNodeResolvesToComment() {
        let syntax = resolver(nodeTypes: ["comment", "translation_unit"])
            .resolve(at: 0, prefix: "", lineTextBeforeCursor: "// ")
        XCTAssertEqual(syntax, .comment)
    }

    func testStringLiteralNodeResolvesToString() {
        let syntax = resolver(nodeTypes: ["string_literal", "compound_statement"])
            .resolve(at: 0, prefix: "", lineTextBeforeCursor: "\"")
        XCTAssertEqual(syntax, .string)
    }

    func testPreprocNodeResolvesToPreprocessor() {
        let syntax = resolver(nodeTypes: ["preproc_include", "translation_unit"])
            .resolve(at: 0, prefix: "", lineTextBeforeCursor: "#include ")
        XCTAssertEqual(syntax, .preprocessor)
    }

    func testFieldExpressionResolvesToMemberAccess() {
        let syntax = resolver(nodeTypes: ["field_expression", "compound_statement"])
            .resolve(at: 0, prefix: "", lineTextBeforeCursor: "point.")
        XCTAssertEqual(syntax, .memberAccess)
    }

    func testCompoundStatementResolvesToStatement() {
        let syntax = resolver(nodeTypes: ["compound_statement"])
            .resolve(at: 0, prefix: "", lineTextBeforeCursor: "    ")
        XCTAssertEqual(syntax, .statement)
    }

    func testTranslationUnitResolvesToTopLevel() {
        let syntax = resolver(nodeTypes: ["translation_unit"])
            .resolve(at: 0, prefix: "", lineTextBeforeCursor: "")
        XCTAssertEqual(syntax, .topLevel)
    }

    func testTextFallbackDetectsPreprocessorWithoutATree() {
        let syntax = resolver(nodeTypes: [])
            .resolve(at: 0, prefix: "#inc", lineTextBeforeCursor: "#inc")
        XCTAssertEqual(syntax, .preprocessor)
    }

    func testTextFallbackDetectsMemberAccessAfterADot() {
        let syntax = resolver(nodeTypes: [])
            .resolve(at: 0, prefix: "", lineTextBeforeCursor: "point.")
        XCTAssertEqual(syntax, .memberAccess)
    }

    func testTextFallbackDetectsLineComments() {
        let syntax = resolver(nodeTypes: [])
            .resolve(at: 0, prefix: "", lineTextBeforeCursor: "  // note")
        XCTAssertEqual(syntax, .comment)
    }

    func testScopeOperatorAtTopLevelResolvesToMemberAccess() {
        // `template <typename T> std::` parses as an ERROR node under the translation unit.
        let syntax = resolver(nodeTypes: ["namespace_identifier", "ERROR", "translation_unit"])
            .resolve(at: 0, prefix: "", lineTextBeforeCursor: "template <typename T> std::")
        XCTAssertEqual(syntax, .memberAccess)
    }

    func testScopeOperatorWithTypedPrefixResolvesToMemberAccess() {
        let syntax = resolver(nodeTypes: ["identifier", "compound_statement", "translation_unit"])
            .resolve(at: 0, prefix: "vec", lineTextBeforeCursor: "    std::vec")
        XCTAssertEqual(syntax, .memberAccess)
    }

    func testArrowInsideStatementResolvesToMemberAccess() {
        let syntax = resolver(nodeTypes: ["compound_statement", "translation_unit"])
            .resolve(at: 0, prefix: "", lineTextBeforeCursor: "    node->")
        XCTAssertEqual(syntax, .memberAccess)
    }

    func testTextFallbackDetectsMemberAccessWithTypedPrefix() {
        let syntax = resolver(nodeTypes: [])
            .resolve(at: 0, prefix: "x", lineTextBeforeCursor: "point.x")
        XCTAssertEqual(syntax, .memberAccess)
    }

    func testSingleColonIsNotMemberAccess() {
        let syntax = resolver(nodeTypes: ["compound_statement"])
            .resolve(at: 0, prefix: "", lineTextBeforeCursor: "    label:")
        XCTAssertEqual(syntax, .statement)
    }

    func testUnrecognizedNodeTypesResolveToUnknown() {
        let syntax = resolver(nodeTypes: ["some_unmapped_node"])
            .resolve(at: 0, prefix: "", lineTextBeforeCursor: "")
        XCTAssertEqual(syntax, .unknown)
    }
}
