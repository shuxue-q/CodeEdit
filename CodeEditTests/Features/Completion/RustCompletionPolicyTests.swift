//
//  RustCompletionPolicyTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/13/26.
//

import XCTest
import LanguageServerProtocol
@testable import CodeEdit

/// The weights ``CompletionIntentPolicy`` gives Rust candidates, the Rust tables, and their effect on ranking.
@MainActor
final class RustCompletionPolicyTests: XCTestCase {
    private func weight(
        _ kind: LSPCompletionCategory,
        _ intent: CompletionIntent,
        source: CompletionSource = .lsp
    ) -> Double? {
        CompletionIntentPolicy.weight(kind: kind, source: source, intent: intent, isExplicit: false, languageId: "rust")
    }

    // MARK: - Weights

    func testKeywordsAndSnippetsLeadStatementsAndItems() throws {
        for intent in [CompletionIntent.statement, .topLevel] {
            XCTAssertEqual(weight(.snippet, intent, source: .snippet), 1.0, "\(intent)")
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(weight(.keyword, intent, source: .keyword)), 0.9, "\(intent)")
        }
    }

    func testNoLocalKeywordsOrSnippetsAfterDotOrPath() {
        for intent in [CompletionIntent.memberAccess, .scopeAccess] {
            XCTAssertNil(weight(.snippet, intent, source: .snippet), "\(intent)")
            XCTAssertNil(weight(.keyword, intent, source: .keyword), "\(intent)")
            XCTAssertNotNil(weight(.function, intent), "\(intent)")
        }
    }

    /// rust-analyzer's own postfix snippets (`.ref`, `.match`) rank below the receiver's members.
    func testServerPostfixSnippetsTrailMembers() throws {
        let method = try XCTUnwrap(weight(.function, .memberAccess))
        let field = try XCTUnwrap(weight(.variable, .memberAccess))
        let postfix = try XCTUnwrap(weight(.snippet, .memberAccess))
        XCTAssertLessThan(postfix, min(method, field))
    }

    func testModulesAndTypesLeadAPath() throws {
        let module = try XCTUnwrap(weight(.namespace, .scopeAccess))
        let type = try XCTUnwrap(weight(.struct, .scopeAccess))
        let other = try XCTUnwrap(weight(.other, .scopeAccess))
        XCTAssertGreaterThan(module, other)
        XCTAssertGreaterThan(type, other)
    }

    func testAttributesAdmitServerItemsOnly() {
        XCTAssertNotNil(weight(.function, .preprocessor), "Attribute names arrive as functions")
        XCTAssertNotNil(weight(.namespace, .preprocessor), "Paths to attribute macros")
        XCTAssertNil(weight(.keyword, .preprocessor, source: .keyword))
        XCTAssertTrue(TreeSitterSnippetProvider.candidates(languageId: "rust", intent: .preprocessor).isEmpty)
    }

    func testValuesExcludeSnippetsAndNamesStayQuiet() {
        XCTAssertNil(weight(.snippet, .expression, source: .snippet))
        XCTAssertNotNil(weight(.keyword, .expression, source: .keyword))
        XCTAssertFalse(CompletionIntentPolicy.allowsAutomaticCompletion(for: .declarationName))
        XCTAssertTrue(CompletionIntentPolicy.allowsAutomaticCompletion(for: .preprocessor))
    }

    // MARK: - Ranking

    private func lspCandidate(_ label: String, kind: LSPCompletionCategory, sortText: String) -> CompletionCandidate {
        CompletionCandidate(
            id: "lsp.\(label)",
            label: label,
            filterText: label,
            sortText: sortText,
            kind: kind,
            source: .lsp,
            detail: nil,
            documentation: nil,
            payload: .lsp(CompletionItem(label: label))
        )
    }

    private func rank(_ candidates: [CompletionCandidate], intent: CompletionIntent, prefix: String = "") -> [String] {
        CompletionRanker.rank(candidates, prefix: prefix, intent: intent, languageId: "rust").items.map(\.label)
    }

    func testStatementSnippetsJoinTheServerAtAStatement() {
        let candidates = [lspCandidate("matches", kind: .function, sortText: "a")]
            + TreeSitterSnippetProvider.candidates(languageId: "rust", intent: .statement)
        let ranked = rank(candidates, intent: .statement, prefix: "mat")
        XCTAssertEqual(Set(ranked.prefix(2)), ["match", "matches"], "\(ranked)")
    }

    // MARK: - Tables

    private func labels(_ intent: CompletionIntent, kind: LSPCompletionCategory? = nil) -> Set<String> {
        Set(TreeSitterSnippetProvider.candidates(languageId: "rust", intent: intent)
            .filter { kind == nil || $0.kind == kind }
            .map(\.label))
    }

    func testRustTablesAreRegisteredWithUniqueEntries() {
        for intent in CompletionIntent.allCases {
            let ids = TreeSitterSnippetProvider.candidates(languageId: "rust", intent: intent).map(\.id)
            XCTAssertEqual(ids.count, Set(ids).count, "Duplicate entries for \(intent): \(ids)")
        }
    }

    func testSnippetsAreOfferedWhereTheyFit() {
        XCTAssertEqual(
            labels(.topLevel, kind: .snippet),
            ["fn", "impl", "struct", "enum", "trait", "main", "test", "derive", "mod tests"]
        )
        XCTAssertEqual(labels(.statement, kind: .snippet), ["fn", "match", "if let", "while let", "loop", "for"])
        for intent in [CompletionIntent.memberAccess, .scopeAccess, .expression, .typeName, .preprocessor, .string] {
            XCTAssertTrue(labels(intent, kind: .snippet).isEmpty, "\(intent)")
        }
    }

    func testKeywordsAreOfferedWhereTheyFit() {
        XCTAssertTrue(labels(.statement).isSuperset(of: ["let", "if", "match", "return", "loop", "while", "for"]))
        XCTAssertTrue(labels(.topLevel).isSuperset(of: ["fn", "struct", "impl", "use", "mod", "pub", "trait"]))
        XCTAssertFalse(labels(.topLevel).contains("let"))
        XCTAssertFalse(labels(.topLevel).contains("return"))
        XCTAssertTrue(labels(.expression).isSuperset(of: ["true", "None", "Some", "self", "Self", "match", "move"]))
        XCTAssertTrue(labels(.typeName).isSuperset(of: ["dyn", "impl", "mut", "Self"]))
        XCTAssertTrue(labels(.memberAccess).isEmpty)
        XCTAssertTrue(labels(.scopeAccess).isEmpty)
    }

    func testSnippetBodies() throws {
        let candidates = TreeSitterSnippetProvider.candidates(languageId: "rust", intent: .topLevel)
            + TreeSitterSnippetProvider.candidates(languageId: "rust", intent: .statement)
        var bodies: [String: String] = [:]
        for candidate in candidates {
            if case .snippet(let body) = candidate.payload { bodies[candidate.label] = body }
        }
        for (label, body) in bodies {
            XCTAssertFalse(body.contains("\t"), "\(label) uses tabs")
        }
        XCTAssertEqual(bodies["test"], "#[test]\nfn ${1:name}() {\n    $0\n}")
        XCTAssertEqual(bodies["derive"], "#[derive(${1:Debug})]")
        XCTAssertTrue(bodies["mod tests"]?.hasPrefix("#[cfg(test)]\nmod tests {\n    use super::*;") == true)
        XCTAssertTrue(bodies["if let"]?.hasPrefix("if let ${1:Some(value)} = ${2:option} {") == true)
    }
}
