//
//  CMakeCompletionTablesTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import CodeEditSourceEditor
import XCTest
@testable import CodeEdit

@MainActor
final class CMakeCompletionTablesTests: XCTestCase {
    private func candidates(_ intent: CompletionIntent) -> [CompletionCandidate] {
        TreeSitterSnippetProvider.candidates(languageId: "cmake", intent: intent)
    }

    private func labels(_ intent: CompletionIntent, kind: LSPCompletionCategory? = nil) -> Set<String> {
        Set(candidates(intent).filter { kind == nil || $0.kind == kind }.map(\.label))
    }

    // MARK: - Commands

    func testCommandPositionOffersCommandsAndSnippets() {
        for intent in [CompletionIntent.statement, .topLevel, .unknown] {
            let offered = labels(intent)
            XCTAssertTrue(offered.isSuperset(of: Set(CMakeCompletionTables.flowControlCommands)), "\(intent)")
            XCTAssertTrue(offered.isSuperset(of: Set(CMakeCompletionTables.commonCommands)), "\(intent)")
        }
    }

    func testCommandNamesAreOfferedAsFunctionsSoTheyMergeWithTheServer() {
        let commands = candidates(.topLevel).filter { $0.source == .keyword }
        XCTAssertFalse(commands.isEmpty)
        XCTAssertTrue(commands.allSatisfy { $0.kind == .function })
    }

    func testRequestedSnippetsExist() {
        let snippets = labels(.topLevel, kind: .snippet)
        let expected: Set<String> = [
            "cmake_minimum_required", "project", "add_executable", "add_library", "target_link_libraries",
            "if", "if else", "foreach", "function", "macro", "option", "find_package", "install",
            "add_custom_command"
        ]
        XCTAssertTrue(snippets.isSuperset(of: expected), "\(expected.subtracting(snippets))")
    }

    func testSnippetsUseLSPPlaceholdersAndBalancedBlocks() throws {
        let snippets = candidates(.topLevel).filter { $0.kind == .snippet }
        for candidate in snippets {
            guard case .snippet(let body) = candidate.payload else { return XCTFail("\(candidate.label)") }
            XCTAssertTrue(body.contains("${1:") || body.contains("$0"), "\(candidate.label) has no tab stop")
            let parsed = SnippetParser.parse(body)
            XCTAssertFalse(parsed.text.contains("$"), "\(candidate.label) left syntax behind: \(parsed.text)")
            let opening = parsed.text.filter { $0 == "(" }.count
            XCTAssertEqual(opening, parsed.text.filter { $0 == ")" }.count, candidate.label)
        }
    }

    func testBlockSnippetsCloseTheirBlock() throws {
        let pairs = ["if": "endif()", "if else": "endif()", "foreach": "endforeach()", "while": "endwhile()",
                     "function": "endfunction()", "macro": "endmacro()"]
        for (label, closing) in pairs {
            let candidate = try XCTUnwrap(candidates(.statement).first { $0.label == label && $0.kind == .snippet })
            guard case .snippet(let body) = candidate.payload else { return XCTFail(label) }
            XCTAssertTrue(body.hasSuffix(closing), "\(label): \(body)")
            XCTAssertTrue(body.contains("\n  $0\n") || body.contains("\n  $0"), "\(label) places the body at $0")
        }
    }

    func testAddExecutableSnippetInsertsPlaceholders() throws {
        let candidate = try XCTUnwrap(
            candidates(.topLevel).first { $0.label == "add_executable" && $0.kind == .snippet }
        )
        guard case .snippet(let body) = candidate.payload else { return XCTFail("Expected a snippet") }
        let parsed = SnippetParser.parse(body)
        XCTAssertEqual(parsed.text, "add_executable(target main.cpp)")
        XCTAssertEqual(parsed.navigationGroups.count, 3, "Two placeholders and the final stop")
    }

    // MARK: - Arguments and variables

    func testArgumentPositionOffersKeywordArgumentsAndVariables() {
        let offered = labels(.argument)
        XCTAssertTrue(offered.isSuperset(of: Set(CMakeCompletionTables.keywordArguments)))
        XCTAssertTrue(offered.isSuperset(of: Set(CMakeCompletionTables.variables)))
        XCTAssertTrue(offered.isDisjoint(with: ["add_executable", "endif"]), "Commands are not arguments")
        XCTAssertTrue(candidates(.argument).allSatisfy { $0.kind != .snippet })
    }

    func testKeywordArgumentsAreKeywordsAndVariablesAreVariables() {
        let all = candidates(.argument)
        XCTAssertTrue(all.filter { CMakeCompletionTables.keywordArguments.contains($0.label) }.allSatisfy {
            $0.kind == .keyword
        })
        XCTAssertTrue(all.filter { CMakeCompletionTables.variables.contains($0.label) }.allSatisfy {
            $0.kind == .variable
        })
    }

    func testReferenceOffersOnlyVariables() {
        let offered = candidates(.variableReference)
        XCTAssertEqual(Set(offered.map(\.label)), Set(CMakeCompletionTables.variables))
        XCTAssertTrue(offered.allSatisfy { $0.kind == .variable })
    }

    func testNothingIsOfferedInCommentsAndStrings() {
        for intent in [CompletionIntent.comment, .string, .numberLiteral, .memberAccess, .scopeAccess] {
            XCTAssertTrue(candidates(intent).isEmpty, "\(intent)")
        }
    }

    func testEveryRequestedNameIsPresent() {
        let spec = """
        if elseif else endif foreach endforeach while endwhile function endfunction macro endmacro block endblock \
        return break continue cmake_minimum_required project add_executable add_library target_link_libraries \
        target_include_directories target_compile_features target_compile_definitions target_compile_options \
        target_sources set unset option message find_package find_library find_path find_program include \
        include_directories add_subdirectory install add_custom_command add_custom_target add_test enable_testing \
        list string file get_target_property set_target_properties set_property get_property configure_file \
        execute_process math cmake_policy cmake_parse_arguments add_definitions add_compile_options \
        link_directories mark_as_advanced FetchContent_Declare FetchContent_MakeAvailable
        """.split(separator: " ").map(String.init)
        XCTAssertTrue(labels(.topLevel).isSuperset(of: spec), "\(Set(spec).subtracting(labels(.topLevel)))")
    }

    func testIdentifiersAreUnique() {
        for intent in [CompletionIntent.topLevel, .argument, .variableReference] {
            let ids = candidates(intent).map(\.id)
            XCTAssertEqual(ids.count, Set(ids).count, "\(intent)")
        }
    }

    func testOtherLanguagesAreUnaffected() {
        XCTAssertTrue(TreeSitterSnippetProvider.candidates(languageId: "cpp", intent: .argument).isEmpty)
        let cppStatements = TreeSitterSnippetProvider.candidates(languageId: "cpp", intent: .statement)
        XCTAssertFalse(cppStatements.contains { $0.label == "project" })
    }
}
