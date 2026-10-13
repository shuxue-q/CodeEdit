//
//  DartCompletionPolicyTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/13/26.
//

import XCTest
import LanguageServerProtocol
@testable import CodeEdit

/// The Dart weights of ``CompletionIntentPolicy``, the Dart tables, and their effect on ranking.
@MainActor
final class DartCompletionPolicyTests: XCTestCase {
    private func weight(
        _ kind: LSPCompletionCategory,
        _ intent: CompletionIntent,
        source: CompletionSource = .lsp,
        language: String = "dart",
        named: Bool = false
    ) -> Double? {
        CompletionIntentPolicy.weight(
            kind: kind,
            source: source,
            intent: intent,
            isExplicit: false,
            languageId: language,
            isNamedArgument: named
        )
    }

    // MARK: - Weights

    func testNamedArgumentsLeadAnArgumentList() throws {
        let named = try XCTUnwrap(weight(.variable, .argument, named: true))
        for kind in [LSPCompletionCategory.variable, .function, .class, .keyword, .enumMember] {
            XCTAssertGreaterThan(named, try XCTUnwrap(weight(kind, .argument)), "\(kind)")
        }
        XCTAssertNil(weight(.snippet, .argument), "Snippets do not go in an argument list")
        XCTAssertNil(weight(.snippet, .argument, source: .snippet))
    }

    func testVariablesLeadAnInterpolation() throws {
        let variable = try XCTUnwrap(weight(.variable, .variableReference))
        for kind in [LSPCompletionCategory.function, .class, .keyword] {
            XCTAssertGreaterThan(variable, try XCTUnwrap(weight(kind, .variableReference)), "\(kind)")
        }
        XCTAssertGreaterThan(
            try XCTUnwrap(weight(.function, .variableReference)),
            try XCTUnwrap(weight(.class, .variableReference)),
            "`${f()}` is more likely than a type"
        )
        XCTAssertNil(weight(.snippet, .variableReference))
    }

    func testStatementsAndFileScopeAllowKeywordsAndSnippets() throws {
        for intent in [CompletionIntent.statement, .topLevel] {
            XCTAssertNotNil(weight(.keyword, intent, source: .keyword), "\(intent)")
            XCTAssertNotNil(weight(.snippet, intent, source: .snippet), "\(intent)")
        }
        XCTAssertEqual(weight(.snippet, .statement, source: .snippet), 1.0)
        XCTAssertEqual(weight(.snippet, .topLevel, source: .snippet), 1.0)
    }

    func testTypingStaysQuietInPlainStringsButNotInInterpolations() {
        XCTAssertFalse(CompletionIntentPolicy.allowsAutomaticCompletion(for: .string))
        XCTAssertTrue(CompletionIntentPolicy.allowsAutomaticCompletion(for: .variableReference))
        XCTAssertTrue(CompletionIntentPolicy.allowsAutomaticCompletion(for: .argument))
        XCTAssertTrue(CompletionIntentPolicy.allowsAutomaticCompletion(for: .includePath))
    }

    /// CMake keeps its argument and reference weights, and ignores the named-argument flag.
    func testCMakeWeightsAreUnchanged() {
        XCTAssertEqual(weight(.variable, .argument, language: "cmake"), 0.9)
        XCTAssertEqual(weight(.variable, .argument, language: "cmake", named: true), 0.9)
        XCTAssertEqual(weight(.keyword, .argument, language: "cmake"), 0.8)
        XCTAssertNil(weight(.snippet, .argument, language: "cmake"))
        XCTAssertEqual(weight(.variable, .variableReference, language: "cmake"), 1.0)
        XCTAssertNil(weight(.keyword, .variableReference, language: "cmake"))
        XCTAssertEqual(weight(.function, .statement, language: "cmake"), 1.0)
    }

    func testNamedArgumentLabels() {
        XCTAssertTrue(CompletionIntentPolicy.isNamedArgumentLabel("padding: "))
        XCTAssertTrue(CompletionIntentPolicy.isNamedArgumentLabel("child:"))
        XCTAssertFalse(CompletionIntentPolicy.isNamedArgumentLabel("padding"))
        XCTAssertFalse(CompletionIntentPolicy.isNamedArgumentLabel(":"))
        XCTAssertFalse(CompletionIntentPolicy.isNamedArgumentLabel("case x:"))
        XCTAssertFalse(CompletionIntentPolicy.isNamedArgumentLabel("std::"), "Not a C++ scope")
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
        CompletionRanker.rank(candidates, prefix: prefix, intent: intent, languageId: "dart").items.map(\.label)
    }

    /// The server's sort order puts values first here; the named arguments still lead after `(`.
    func testNamedArgumentsRankFirstAfterAnOpeningParenthesis() {
        let candidates = [
            lspCandidate("context", kind: .variable, sortText: "a"),
            lspCandidate("Text", kind: .function, sortText: "b"),
            lspCandidate("padding: ", kind: .variable, sortText: "c"),
            lspCandidate("child: ", kind: .variable, sortText: "d")
        ] + TreeSitterSnippetProvider.candidates(languageId: "dart", intent: .argument)
        let ranked = rank(candidates, intent: .argument)
        XCTAssertEqual(Array(ranked.prefix(2)), ["padding: ", "child: "], "\(ranked)")
        XCTAssertFalse(ranked.contains("stless"))
    }

    func testValuesRankFirstAfterANamedArgument() {
        let candidates = [
            lspCandidate("Text", kind: .function, sortText: "b"),
            lspCandidate("name", kind: .variable, sortText: "a"),
            lspCandidate("Widget", kind: .class, sortText: "c")
        ]
        XCTAssertEqual(rank(candidates, intent: .expression).last, "Widget")
    }

    /// A variable the server ranks between a type and a method leads in an interpolation.
    func testVariablesRankFirstInAnInterpolation() {
        let candidates = [
            lspCandidate("String", kind: .class, sortText: "a"),
            lspCandidate("total", kind: .variable, sortText: "b"),
            lspCandidate("toString", kind: .function, sortText: "c")
        ]
        XCTAssertEqual(rank(candidates, intent: .variableReference, prefix: "t").first, "total")
    }

    // MARK: - Tables

    func testDartTablesAreRegisteredWithUniqueEntries() {
        var ids: [String] = []
        for intent in CompletionIntent.allCases {
            ids += TreeSitterSnippetProvider.candidates(languageId: "dart", intent: intent).map(\.id)
        }
        let unique = Set(ids)
        XCTAssertTrue(unique.contains("snippet.dart.stless"))
        let perIntent = CompletionIntent.allCases.map {
            TreeSitterSnippetProvider.candidates(languageId: "dart", intent: $0).map(\.id)
        }
        for list in perIntent {
            XCTAssertEqual(list.count, Set(list).count, "Duplicate entries: \(list)")
        }
    }

    private func labels(_ intent: CompletionIntent, kind: LSPCompletionCategory? = nil) -> Set<String> {
        Set(TreeSitterSnippetProvider.candidates(languageId: "dart", intent: intent)
            .filter { kind == nil || $0.kind == kind }
            .map(\.label))
    }

    func testSnippetsAreOfferedWhereTheyFit() {
        let fileSnippets = labels(.topLevel, kind: .snippet)
        XCTAssertEqual(fileSnippets, ["stless", "stful", "build", "main"])
        let statementSnippets = labels(.statement, kind: .snippet)
        XCTAssertEqual(statementSnippets, ["for", "forin", "if", "switch", "try"])
        for intent in [CompletionIntent.memberAccess, .argument, .expression, .variableReference, .string] {
            XCTAssertTrue(labels(intent, kind: .snippet).isEmpty, "\(intent)")
        }
    }

    func testKeywordsAreOfferedWhereTheyFit() {
        XCTAssertTrue(labels(.statement).isSuperset(of: ["if", "return", "final", "var", "const", "await"]))
        XCTAssertTrue(labels(.topLevel).isSuperset(of: ["import", "class", "final", "static", "void"]))
        XCTAssertFalse(labels(.topLevel).contains("return"))
        XCTAssertTrue(labels(.argument).isSuperset(of: ["const", "true", "null"]))
        XCTAssertTrue(labels(.typeName).isSuperset(of: ["required", "this", "super", "void"]))
        XCTAssertTrue(labels(.memberAccess).isEmpty)
        XCTAssertTrue(labels(.variableReference).isEmpty)
    }

    func testSnippetBodiesUseMirroredPlaceholders() throws {
        let stless = try XCTUnwrap(
            TreeSitterSnippetProvider.candidates(languageId: "dart", intent: .topLevel).first { $0.label == "stless" }
        )
        guard case .snippet(let body) = stless.payload else { return XCTFail("Not a snippet") }
        XCTAssertTrue(body.hasPrefix("class ${1:MyWidget} extends StatelessWidget {"))
        XCTAssertTrue(body.contains("const ${1:MyWidget}({super.key});"))
        XCTAssertFalse(body.contains("\t"), "Two-space indentation")
    }

    // MARK: - Server responses

    func testResponseKeepsIsIncompleteAndLabelDetails() throws {
        let json = """
        {"isIncomplete": true, "items": [
          {"label": "Uint8List", "kind": 7,
           "labelDetails": {"detail": "(int length)", "description": "dart:typed_data"}},
          {"label": "padding: ", "kind": 6}
        ]}
        """
        let response = try JSONDecoder().decode(ScoredCompletionResponse.self, from: Data(json.utf8))
        XCTAssertTrue(response.isIncomplete)
        XCTAssertEqual(response.labelDetails.count, 2)
        XCTAssertEqual(response.labelDetails[0]?.description, "dart:typed_data")
        XCTAssertEqual(response.labelDetails[0]?.displayText, "(int length)  dart:typed_data")
        XCTAssertNil(response.labelDetails[1])
    }

    func testBareArraysAndCompleteListsAreNotIncomplete() throws {
        let array = try JSONDecoder().decode(ScoredCompletionResponse.self, from: Data(#"[{"label": "a"}]"#.utf8))
        XCTAssertFalse(array.isIncomplete)
        let list = try JSONDecoder().decode(
            ScoredCompletionResponse.self,
            from: Data(#"{"isIncomplete": false, "items": []}"#.utf8)
        )
        XCTAssertFalse(list.isIncomplete)
        XCTAssertEqual(CompletionLabelDetails(detail: " ", description: nil).displayText, nil)
    }

    func testOnlyDartReRequestsIncompleteLists() {
        XCTAssertEqual(LSPCompletionProvider.incompleteListLanguageIds, ["dart"])
    }
}
