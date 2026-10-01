//
//  TreeSitterSnippetProviderTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/30/26.
//

import XCTest
@testable import CodeEdit

@MainActor
final class TreeSitterSnippetProviderTests: XCTestCase {
    private func labels(_ languageId: String, _ intent: CompletionIntent) -> Set<String> {
        Set(TreeSitterSnippetProvider.candidates(languageId: languageId, intent: intent).map(\.label))
    }

    func testStatementStartOffersControlFlow() {
        let offered = labels("cpp", .statement)
        XCTAssertTrue(offered.isSuperset(of: ["for", "while", "if", "switch", "return", "int", "for range"]))
        XCTAssertFalse(offered.contains("namespace"), "namespace only belongs at file scope")
    }

    func testExpressionOffersValuesNotStatements() {
        let offered = labels("cpp", .expression)
        XCTAssertTrue(offered.isSuperset(of: ["nullptr", "true", "sizeof", "static_cast"]))
        XCTAssertTrue(offered.isDisjoint(with: ["for", "return", "class"]))
    }

    func testTypePositionOffersTypesAndQualifiers() {
        let offered = labels("cpp", .typeName)
        XCTAssertTrue(offered.isSuperset(of: ["int", "const", "unsigned", "auto"]))
        XCTAssertTrue(offered.isDisjoint(with: ["return", "nullptr", "for"]))
    }

    func testFileScopeOffersDeclarations() {
        let offered = labels("cpp", .topLevel)
        XCTAssertTrue(offered.isSuperset(of: ["class", "struct", "namespace", "template", "main"]))
        XCTAssertFalse(offered.contains("return"))
    }

    func testAccessIntentsOfferNothing() {
        XCTAssertTrue(labels("cpp", .memberAccess).isEmpty)
        XCTAssertTrue(labels("cpp", .scopeAccess).isEmpty)
        XCTAssertTrue(labels("cpp", .caseLabel).isEmpty)
        XCTAssertTrue(labels("cpp", .includePath).isEmpty)
    }

    func testCOmitsCPlusPlusKeywords() {
        let offered = labels("c", .unknown)
        XCTAssertTrue(offered.isDisjoint(with: ["class", "nullptr", "namespace", "template"]))
        XCTAssertTrue(offered.contains("struct"))
    }

    func testIncludeSnippetsKeepTheHash() throws {
        let includes = TreeSitterSnippetProvider.candidates(languageId: "c", intent: .preprocessor)
        XCTAssertEqual(includes.count, 2)
        for candidate in includes {
            guard case .snippet(let body) = candidate.payload else { return XCTFail("Expected a snippet") }
            // The snippet replaces the typed `#inc…` word, so the body must restore the `#`.
            XCTAssertTrue(body.hasPrefix("#include "), body)
        }
    }

    func testIdentifiersAreUniquePerLanguage() {
        for languageId in ["c", "cpp"] {
            for intent in CompletionIntent.allCases {
                let ids = TreeSitterSnippetProvider.candidates(languageId: languageId, intent: intent).map(\.id)
                XCTAssertEqual(ids.count, Set(ids).count, "\(languageId) \(intent)")
            }
        }
    }
}
