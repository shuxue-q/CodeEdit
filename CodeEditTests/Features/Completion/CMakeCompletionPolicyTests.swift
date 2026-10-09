//
//  CMakeCompletionPolicyTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
@testable import CodeEdit

@MainActor
final class CMakeCompletionPolicyTests: XCTestCase {
    private func weight(
        _ kind: LSPCompletionCategory,
        _ intent: CompletionIntent,
        source: CompletionSource = .lsp,
        language: String = "cmake",
        explicit: Bool = false
    ) -> Double? {
        CompletionIntentPolicy.weight(
            kind: kind,
            source: source,
            intent: intent,
            isExplicit: explicit,
            languageId: language
        )
    }

    private func assertPrefers(
        _ preferred: LSPCompletionCategory,
        over other: LSPCompletionCategory,
        in intent: CompletionIntent,
        line: UInt = #line
    ) throws {
        let preferredWeight = try XCTUnwrap(weight(preferred, intent), line: line)
        let otherWeight = try XCTUnwrap(weight(other, intent), line: line)
        XCTAssertGreaterThan(preferredWeight, otherWeight, "\(preferred) over \(other) in \(intent)", line: line)
    }

    // MARK: - Typing

    func testTypingOpensTheWindowWhereCMakeNeedsIt() {
        for intent in [CompletionIntent.statement, .topLevel, .argument, .variableReference] {
            XCTAssertTrue(CompletionIntentPolicy.allowsAutomaticCompletion(for: intent), "\(intent)")
        }
    }

    func testTypingStaysQuietInCommentsAndPlainQuotedText() {
        for intent in [CompletionIntent.comment, .string] {
            XCTAssertFalse(CompletionIntentPolicy.allowsAutomaticCompletion(for: intent), "\(intent)")
            XCTAssertNil(weight(.function, intent))
            XCTAssertEqual(weight(.function, intent, explicit: true), 0.1)
        }
    }

    // MARK: - Command position

    func testCommandsComeFirstAtCommandPosition() throws {
        for intent in [CompletionIntent.statement, .topLevel] {
            try assertPrefers(.function, over: .variable, in: intent)
            try assertPrefers(.function, over: .namespace, in: intent)
            try assertPrefers(.snippet, over: .variable, in: intent)
            try assertPrefers(.keyword, over: .variable, in: intent)
            try assertPrefers(.function, over: .snippet, in: intent)
        }
    }

    func testCFamilyStatementWeightsAreUnchanged() throws {
        for language in ["", "cpp", "c"] {
            XCTAssertEqual(weight(.snippet, .statement, source: .snippet, language: language), 1.0)
            XCTAssertEqual(weight(.function, .statement, source: .lsp, language: language), 0.8)
            XCTAssertEqual(weight(.class, .topLevel, source: .lsp, language: language), 1.0)
        }
    }

    // MARK: - Variables

    func testVariablesComeFirstInsideAReference() throws {
        try assertPrefers(.variable, over: .function, in: .variableReference)
        try assertPrefers(.variable, over: .namespace, in: .variableReference)
        try assertPrefers(.macro, over: .function, in: .variableReference)
    }

    func testReferencesExcludeSnippetsAndKeywords() {
        XCTAssertNil(weight(.snippet, .variableReference, source: .snippet))
        XCTAssertNil(weight(.keyword, .variableReference, source: .keyword))
        XCTAssertNil(weight(.keyword, .variableReference, source: .lsp))
        XCTAssertNotNil(weight(.variable, .variableReference, source: .keyword), "The variable table is a local source")
    }

    // MARK: - Arguments

    func testArgumentsExcludeSnippetsButKeepKeywords() {
        XCTAssertNil(weight(.snippet, .argument, source: .snippet))
        XCTAssertNotNil(weight(.keyword, .argument, source: .keyword))
        XCTAssertNotNil(weight(.variable, .argument, source: .keyword))
    }

    func testArgumentsPreferTargetsAndModulesToCommands() throws {
        try assertPrefers(.variable, over: .function, in: .argument)
        try assertPrefers(.namespace, over: .function, in: .argument)
        try assertPrefers(.file, over: .function, in: .argument)
    }

    func testCapitalizedPrefixesBoostKeywordArguments() {
        XCTAssertEqual(CompletionIntentPolicy.prefixShapeBonus(kind: .keyword, prefix: "PU", intent: .argument), 0.3)
        XCTAssertEqual(CompletionIntentPolicy.prefixShapeBonus(kind: .keyword, prefix: "pu", intent: .argument), 0)
        XCTAssertEqual(CompletionIntentPolicy.prefixShapeBonus(kind: .keyword, prefix: "P", intent: .argument), 0)
        XCTAssertEqual(CompletionIntentPolicy.prefixShapeBonus(kind: .variable, prefix: "PU", intent: .argument), 0)
        XCTAssertEqual(CompletionIntentPolicy.prefixShapeBonus(kind: .keyword, prefix: "PU", intent: .expression), 0)
        XCTAssertEqual(CompletionIntentPolicy.prefixShapeBonus(kind: .keyword, prefix: "PU"), 0)
        XCTAssertEqual(CompletionIntentPolicy.prefixShapeBonus(kind: .macro, prefix: "MAX_"), 0.3, "Unchanged")
    }

    func testDocumentWordsAreOfferedInArgumentsAndReferences() {
        XCTAssertNotNil(weight(.other, .argument, source: .word))
        XCTAssertNotNil(weight(.other, .variableReference, source: .word))
        XCTAssertNil(weight(.other, .comment, source: .word))
    }

    // MARK: - Ranking end to end

    private func ranked(
        _ candidates: [CompletionCandidate],
        prefix: String,
        intent: CompletionIntent
    ) -> [String] {
        let deduplicated = CompletionDeduplicator.deduplicate(candidates)
        return CompletionRanker.rank(deduplicated, prefix: prefix, intent: intent, languageId: "cmake")
            .items.map(\.label)
    }

    private func server(_ label: String, _ kind: LSPCompletionCategory) -> CompletionCandidate {
        CompletionCandidate(
            id: "lsp.\(label)",
            label: label,
            filterText: label,
            kind: kind,
            source: .lsp,
            // Not plain text, like a server item with a text edit: the deduplicator keeps it next to a snippet.
            payload: .snippet(body: label)
        )
    }

    func testCommandPrefixListsCommandsAndSnippetsBeforeVariables() {
        let tables = TreeSitterSnippetProvider.candidates(languageId: "cmake", intent: .topLevel)
        let candidates = tables + [server("add_executable", .function), server("ADD_VAR", .variable)]
        let labels = ranked(candidates, prefix: "add_", intent: .topLevel)
        XCTAssertEqual(labels.filter { $0 == "add_executable" }.count, 2, "The server's command and the snippet")
        XCTAssertTrue(labels.contains("add_library"))
        XCTAssertEqual(labels.last, "ADD_VAR", "A variable is the weakest match at command position")
        XCTAssertTrue(labels.dropLast().allSatisfy { $0.hasPrefix("add_") })
    }

    func testUppercasePrefixInArgumentsPutsKeywordsFirst() {
        let tables = TreeSitterSnippetProvider.candidates(languageId: "cmake", intent: .argument)
        let candidates = tables + [server("PUBLIC_HEADERS", .variable), server("Publish", .variable)]
        let labels = ranked(candidates, prefix: "PU", intent: .argument)
        XCTAssertEqual(labels.first, "PUBLIC")
        XCTAssertTrue(labels.contains("PRIVATE") == false, "PRIVATE does not match PU")
    }

    func testVariablePrefixInsideAReferenceListsVariables() {
        let tables = TreeSitterSnippetProvider.candidates(languageId: "cmake", intent: .variableReference)
        let candidates = tables + [server("CMAKE_MY_OWN", .variable), server("cmake_policy", .function)]
        let labels = ranked(candidates, prefix: "CMAKE_", intent: .variableReference)
        XCTAssertTrue(labels.contains("CMAKE_SOURCE_DIR"))
        XCTAssertTrue(labels.contains("CMAKE_MY_OWN"))
        XCTAssertFalse(labels.contains("PUBLIC"), "Keywords are not variables")
        XCTAssertEqual(labels.last, "cmake_policy", "A command is the weakest match for a variable")
    }
}
