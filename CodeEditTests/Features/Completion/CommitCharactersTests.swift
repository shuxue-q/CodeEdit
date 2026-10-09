//
//  CommitCharactersTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
import LanguageServerProtocol
@testable import CodeEdit

final class CommitCharactersTests: XCTestCase {
    private func candidate(
        _ label: String,
        source: CompletionSource = .lsp,
        kind: LSPCompletionCategory = .variable,
        commitCharacters: [String]? = nil
    ) -> CompletionCandidate {
        let item = CompletionItem(label: label, commitCharacters: commitCharacters)
        return CompletionCandidate(
            id: UUID().uuidString,
            label: label,
            filterText: label,
            kind: kind,
            source: source,
            payload: .lsp(item)
        )
    }

    func testCFamilyDefaultsApplyToLanguageServerItems() {
        let item = candidate("foo")
        let characters = CommitCharacters.characters(for: item, languageId: "cpp", prefix: "fo", pool: [item])
        XCTAssertEqual(characters, CommitCharacters.cFamily)
        XCTAssertTrue(characters.isSuperset(of: ["(", ".", ";", ",", ")", "[", ">"]))
    }

    func testOtherLanguagesCommitNothingByDefault() {
        let item = candidate("foo")
        XCTAssertTrue(CommitCharacters.characters(for: item, languageId: "swift", prefix: "fo", pool: [item]).isEmpty)
    }

    func testServerCommitCharactersTakePrecedence() {
        let item = candidate("foo", commitCharacters: [".", ","])
        let characters = CommitCharacters.characters(for: item, languageId: "typescript", prefix: "fo", pool: [item])
        XCTAssertEqual(characters, [".", ","])
    }

    func testEmptyPrefixNeverCommits() {
        let item = candidate("foo")
        XCTAssertTrue(CommitCharacters.characters(for: item, languageId: "cpp", prefix: "", pool: [item]).isEmpty)
    }

    func testNonServerAndPathItemsNeverCommit() {
        for source in [CompletionSource.snippet, .keyword, .ai] {
            let item = candidate("if", source: source)
            XCTAssertTrue(CommitCharacters.characters(for: item, languageId: "cpp", prefix: "i", pool: [item]).isEmpty)
        }
        let file = candidate("stdio.h", kind: .file)
        XCTAssertTrue(CommitCharacters.characters(for: file, languageId: "cpp", prefix: "std", pool: [file]).isEmpty)
    }

    func testTypingAnotherCandidatesExactNameDoesNotCommitTheHighlightedRow() {
        let integer = candidate("int", kind: .keyword)
        let variable = candidate("i")
        let characters = CommitCharacters.characters(
            for: integer,
            languageId: "cpp",
            prefix: "i",
            pool: [integer, variable]
        )
        XCTAssertTrue(characters.isEmpty)
        let own = CommitCharacters.characters(for: variable, languageId: "cpp", prefix: "i", pool: [integer, variable])
        XCTAssertFalse(own.isEmpty, "The row that is the typed name still commits")
    }

    func testRowNameStripsSignatureAndTemplateArguments() {
        XCTAssertEqual(CompletionDeduplicator.symbolName(of: " foo(int a)"), "foo")
        XCTAssertEqual(CompletionDeduplicator.symbolName(of: "•vector<T>"), "vector")
    }

    func testSettingDefaultsToEnabled() throws {
        let decoded = try JSONDecoder().decode(
            SettingsData.TextEditingSettings.CompletionBehaviorSettings.self,
            from: Data("{}".utf8)
        )
        XCTAssertTrue(decoded.commitCharactersEnabled)
    }

    func testFunctionParenthesesAreSuppressedForCharactersThatAreTheCall() {
        for typed in ["(", ")", "["] as [Character] {
            XCTAssertNil(
                FunctionCallInsertion.insertion(
                    label: "foo(int)",
                    detail: nil,
                    nextCharacter: nil,
                    commitCharacter: typed
                ),
                "\(typed)"
            )
        }
        for typed in [".", ",", ";"] as [Character] {
            XCTAssertEqual(
                FunctionCallInsertion.insertion(
                    label: "foo(int)",
                    detail: nil,
                    nextCharacter: nil,
                    commitCharacter: typed
                ),
                .init(text: "()", caretOffset: 2),
                "\(typed)"
            )
        }
    }
}
