//
//  CompletionIntentPolicyTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/30/26.
//

import XCTest
@testable import CodeEdit

final class CompletionIntentPolicyTests: XCTestCase {
    private func weight(
        _ kind: LSPCompletionCategory,
        _ source: CompletionSource = .lsp,
        _ intent: CompletionIntent,
        explicit: Bool = false
    ) -> Double? {
        CompletionIntentPolicy.weight(kind: kind, source: source, intent: intent, isExplicit: explicit)
    }

    func testTypingStaysQuietWhereAPopupGetsInTheWay() {
        for intent in [CompletionIntent.comment, .string, .numberLiteral, .declarationName] {
            XCTAssertFalse(CompletionIntentPolicy.allowsAutomaticCompletion(for: intent), "\(intent)")
        }
        for intent in [CompletionIntent.memberAccess, .statement, .expression, .typeName, .unknown] {
            XCTAssertTrue(CompletionIntentPolicy.allowsAutomaticCompletion(for: intent), "\(intent)")
        }
    }

    func testQuietIntentsOfferEverythingOnlyOnExplicitRequest() {
        XCTAssertNil(weight(.variable, .lsp, .declarationName))
        XCTAssertEqual(weight(.variable, .lsp, .declarationName, explicit: true), 0.1)
    }

    func testMemberAndScopeAccessExcludeLocalSnippetsAndKeywords() {
        for intent in [CompletionIntent.memberAccess, .scopeAccess, .caseLabel, .includePath] {
            XCTAssertNil(weight(.snippet, .snippet, intent), "\(intent)")
            XCTAssertNil(weight(.keyword, .keyword, intent), "\(intent)")
        }
    }

    private func assertPrefers(
        _ preferred: LSPCompletionCategory,
        over other: LSPCompletionCategory,
        in intent: CompletionIntent,
        line: UInt = #line
    ) throws {
        let preferredWeight = try XCTUnwrap(weight(preferred, .lsp, intent), line: line)
        let otherWeight = try XCTUnwrap(weight(other, .lsp, intent), line: line)
        XCTAssertGreaterThan(preferredWeight, otherWeight, "\(intent)", line: line)
    }

    func testEachIntentPrefersTheKindsItExpects() throws {
        try assertPrefers(.function, over: .class, in: .memberAccess)
        try assertPrefers(.namespace, over: .macro, in: .scopeAccess)
        try assertPrefers(.enumMember, over: .function, in: .caseLabel)
        try assertPrefers(.struct, over: .variable, in: .typeName)
        try assertPrefers(.variable, over: .class, in: .expression)
        try assertPrefers(.file, over: .macro, in: .includePath)
        try assertPrefers(.snippet, over: .variable, in: .statement)
        try assertPrefers(.class, over: .variable, in: .topLevel)
        XCTAssertNil(weight(.snippet, .snippet, .expression), "Statement snippets make no sense inside an expression")
    }

    func testPrefixShapeHintsAtTheKind() {
        XCTAssertGreaterThan(CompletionIntentPolicy.prefixShapeBonus(kind: .macro, prefix: "MAX_"), 0)
        XCTAssertEqual(CompletionIntentPolicy.prefixShapeBonus(kind: .variable, prefix: "MAX_"), 0)
        XCTAssertGreaterThan(CompletionIntentPolicy.prefixShapeBonus(kind: .struct, prefix: "Poi"), 0)
        XCTAssertEqual(CompletionIntentPolicy.prefixShapeBonus(kind: .struct, prefix: "poi"), 0)
        XCTAssertEqual(CompletionIntentPolicy.prefixShapeBonus(kind: .macro, prefix: "M"), 0, "One letter says nothing")
    }
}
