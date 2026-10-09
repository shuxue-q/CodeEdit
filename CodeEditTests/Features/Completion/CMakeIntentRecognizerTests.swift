//
//  CMakeIntentRecognizerTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
@testable import CodeEdit

final class CMakeIntentRecognizerTests: XCTestCase {
    /// Node ancestry for a command name typed in an `if` body.
    private let ifBody = ["body", "if_condition", "source_file"]
    /// Node ancestry for a command name typed in a function body.
    private let functionBody = ["body", "function_def", "source_file"]
    /// Node ancestry for a command name typed in nested blocks.
    private let nestedBody = ["body", "foreach_loop", "body", "function_def", "source_file"]
    /// Node ancestry at file scope.
    private let file = ["source_file"]
    /// Node ancestry for an unfinished command name, which parses as an error.
    private let unfinishedCommand = ["identifier", "ERROR", "source_file"]
    /// Node ancestry inside a command's arguments.
    private let arguments = ["argument_list", "normal_command", "source_file"]
    /// Node ancestry inside a quoted argument.
    private let quoted = ["quoted_element", "quoted_argument", "argument", "argument_list", "normal_command"]

    /// Recognizes the intent at the end of `line`, where the typed prefix is the trailing word, the
    /// way the aggregator splits it (`$` and `#` belong to a word, `{` does not).
    private func intent(_ line: String, nodeTypes: [String] = []) -> CompletionIntent {
        let prefix = String(
            line.reversed().prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" || $0 == "#" }.reversed()
        )
        return CompletionIntentRecognizer { _ in nodeTypes }
            .recognize(at: 0, prefix: prefix, lineTextBeforeCursor: line, languageId: "cmake")
    }

    // MARK: - Command position

    func testCommandPositionAtFileScope() {
        XCTAssertEqual(intent("add_", nodeTypes: unfinishedCommand), .topLevel)
        XCTAssertEqual(intent("", nodeTypes: file), .topLevel)
        XCTAssertEqual(intent("add_", nodeTypes: file), .topLevel)
    }

    func testCommandPositionInsideBlocksIsAStatement() {
        XCTAssertEqual(intent("  add_", nodeTypes: ifBody), .statement)
        XCTAssertEqual(intent("  add_", nodeTypes: functionBody), .statement)
        XCTAssertEqual(intent("    tar", nodeTypes: nestedBody), .statement)
        XCTAssertEqual(intent("  ", nodeTypes: ["body", "macro_def", "source_file"]), .statement)
        XCTAssertEqual(intent("  ", nodeTypes: ["body", "while_loop", "source_file"]), .statement)
        XCTAssertEqual(intent("  ", nodeTypes: ["body", "block_def", "source_file"]), .statement)
    }

    func testCommandPositionOnAnExistingCommandName() {
        // The cursor at the end of `endif` in `endif()` is on the name, not in the parentheses. The
        // `if_condition` that wraps the whole block makes this a block scope.
        let types = ["endif", "endif_command", "if_condition", "source_file"]
        XCTAssertEqual(intent("endif", nodeTypes: types), .statement)
        XCTAssertEqual(intent("  set", nodeTypes: ["identifier", "normal_command"] + ifBody), .statement)
        XCTAssertEqual(intent("proj", nodeTypes: ["identifier", "normal_command", "source_file"]), .topLevel)
    }

    func testCommandPositionWithoutATreeUsesIndentation() {
        XCTAssertEqual(intent("add_"), .topLevel)
        XCTAssertEqual(intent(""), .topLevel)
        XCTAssertEqual(intent("  add_"), .statement)
        XCTAssertEqual(intent("\ttarget_"), .statement)
    }

    func testANewCommandCanFollowAFinishedOne() {
        XCTAssertEqual(intent("endif() add_", nodeTypes: file), .topLevel)
        XCTAssertEqual(intent("if(A) mess", nodeTypes: functionBody), .statement)
        XCTAssertEqual(intent("project(x) add_"), .statement)
        XCTAssertEqual(intent("#[[ note ]] add_"), .statement)
    }

    // MARK: - Arguments

    func testArgumentAfterAnOpenParenthesis() {
        XCTAssertEqual(intent("set(CMAKE_"), .argument)
        XCTAssertEqual(intent("set(CMAKE_", nodeTypes: arguments), .argument)
        XCTAssertEqual(intent("set(", nodeTypes: ["normal_command", "source_file"]), .argument)
        XCTAssertEqual(intent("project(", nodeTypes: file), .argument)
        XCTAssertEqual(intent("  add_executable(app ", nodeTypes: arguments + functionBody), .argument)
    }

    func testKeywordArgumentPosition() {
        XCTAssertEqual(intent("target_link_libraries(app PU"), .argument)
        XCTAssertEqual(intent("target_link_libraries(app PU", nodeTypes: arguments), .argument)
        XCTAssertEqual(intent("find_package(Boost REQ"), .argument)
        XCTAssertEqual(intent("if(NOT "), .argument)
        XCTAssertEqual(intent("foreach(x IN LIS"), .argument)
        let ifHeader = ["argument_list", "if_command", "if_condition", "source_file"]
        XCTAssertEqual(intent("if(A AND ", nodeTypes: ifHeader), .argument)
    }

    func testArgumentsContinuingOnLaterLines() {
        XCTAssertEqual(intent("    PUB", nodeTypes: ["argument_list", "ERROR"]), .argument)
        XCTAssertEqual(intent("    ", nodeTypes: arguments), .argument)
        XCTAssertEqual(intent("    main.cpp util", nodeTypes: arguments), .argument)
        XCTAssertEqual(intent("    main.cpp util"), .argument)
    }

    func testPathsAndVersionsAreArgumentsNotMembersOrNumbers() {
        XCTAssertEqual(intent("add_executable(app src/main.cpp"), .argument)
        XCTAssertEqual(intent("add_executable(app src/main.cpp", nodeTypes: arguments), .argument)
        XCTAssertEqual(intent("cmake_minimum_required(VERSION 3.20"), .argument)
        XCTAssertEqual(intent("cmake_minimum_required(VERSION 3.20", nodeTypes: arguments), .argument)
        XCTAssertEqual(intent("find_package(Boost 1"), .argument)
        XCTAssertEqual(intent("target_link_libraries(app ../lib/libfoo.a"), .argument)
        XCTAssertEqual(intent("set(X a->b"), .argument)
        XCTAssertEqual(intent("set(X a::b"), .argument)
    }

    func testDoubleSlashIsNotACommentInCMake() {
        XCTAssertEqual(intent("add_subdirectory(// "), .argument)
        XCTAssertEqual(intent("add_subdirectory(//dir"), .argument)
    }

    func testBracketsInArgumentsAreOrdinaryCharacters() {
        XCTAssertEqual(intent("set(X [abc] "), .argument)
        XCTAssertEqual(intent("set(X a[0"), .argument)
    }

    // MARK: - Variable references

    func testVariableReferenceInsideBraces() {
        XCTAssertEqual(intent("set(X ${CMAKE_"), .variableReference)
        XCTAssertEqual(intent("set(X ${"), .variableReference)
        XCTAssertEqual(intent("${PRO"), .variableReference)
        XCTAssertEqual(intent("message(STATUS ${A}${B"), .variableReference)
        XCTAssertEqual(intent("set(X ${CMAKE_", nodeTypes: arguments), .variableReference)
    }

    func testEnvironmentAndCacheReferences() {
        XCTAssertEqual(intent("set(X $ENV{HO"), .variableReference)
        XCTAssertEqual(intent("set(X $ENV{"), .variableReference)
        XCTAssertEqual(intent("set(X $CACHE{MY"), .variableReference)
        XCTAssertEqual(intent("set(X $CACHE{"), .variableReference)
    }

    func testNestedReferenceIsAVariableReference() {
        XCTAssertEqual(intent("set(X ${PREFIX_${NA"), .variableReference)
        XCTAssertEqual(intent("set(X ${PREFIX_${NAME}_"), .variableReference)
    }

    func testReferencesExpandInsideQuotedArguments() {
        XCTAssertEqual(intent("message(STATUS \"dir: ${CMAKE_"), .variableReference)
        XCTAssertEqual(intent("message(STATUS \"dir: ${CMAKE_", nodeTypes: quoted), .variableReference)
        XCTAssertEqual(intent("message(\"$ENV{HO"), .variableReference)
    }

    func testReferenceFromTheTreeAloneNeedsAPrefix() {
        let reference = ["variable", "normal_var", "variable_ref", "unquoted_argument", "argument", "argument_list"]
        XCTAssertEqual(intent("foo", nodeTypes: reference), .variableReference)
        XCTAssertEqual(intent("set(X ${A}", nodeTypes: reference), .argument, "Right after `}` nothing is named")
    }

    func testClosedAndEscapedReferencesAreNotOpen() {
        XCTAssertEqual(intent("set(X ${A} B"), .argument)
        XCTAssertEqual(intent("set(X \\${CMAKE_"), .argument)
        XCTAssertEqual(intent("message(\"\\${CMAKE_"), .string)
    }

    // MARK: - Comments and strings

    func testLineComments() {
        XCTAssertEqual(intent("# note"), .comment)
        XCTAssertEqual(intent("  # note"), .comment)
        XCTAssertEqual(intent("add_executable(app) # trailing note"), .comment)
        XCTAssertEqual(intent("set(X a # note"), .comment)
        XCTAssertEqual(intent("#"), .comment)
        XCTAssertEqual(intent("add_executable(app) #no"), .comment)
        XCTAssertEqual(intent("# note ${CMAKE_"), .comment)
    }

    func testBracketComments() {
        XCTAssertEqual(intent("#[[ open note"), .comment)
        XCTAssertEqual(intent("#[==[ open ]] still"), .comment)
        let inside = ["bracket_comment_content", "bracket_comment", "source_file"]
        XCTAssertEqual(intent("middle of a note", nodeTypes: inside), .comment)
    }

    func testCommentNodesWinOverTheLine() {
        XCTAssertEqual(intent("note", nodeTypes: ["line_comment", "body", "if_condition", "source_file"]), .comment)
        XCTAssertEqual(intent("  more", nodeTypes: ["bracket_comment", "source_file"]), .comment)
    }

    func testQuotedArgumentsAreStrings() {
        XCTAssertEqual(intent("message(STATUS \"hel"), .string)
        XCTAssertEqual(intent("message(\"a \\\" qu"), .string)
        XCTAssertEqual(intent("message(STATUS \"hel", nodeTypes: quoted), .string)
        XCTAssertEqual(intent("continued text", nodeTypes: quoted), .string)
    }

    func testHashInsideAQuoteIsNotAComment() {
        XCTAssertEqual(intent("set(X \"a # b"), .string)
        XCTAssertEqual(intent("set(X \"a #b"), .string)
    }

    func testBracketArgumentsAreStrings() {
        XCTAssertEqual(intent("set(X [[open text"), .string)
        XCTAssertEqual(intent("set(X [==[open ]] text"), .string)
        XCTAssertEqual(intent("text", nodeTypes: ["bracket_argument", "argument"]), .string)
        XCTAssertEqual(intent("set(X [[closed]] "), .argument)
    }

    func testCursorRightAfterAClosingQuoteIsNotInTheString() {
        XCTAssertEqual(intent("message(\"done\""), .argument)
        XCTAssertEqual(intent("message(\"done\"", nodeTypes: quoted), .argument)
        XCTAssertEqual(intent("message(\"done\" ", nodeTypes: arguments), .argument)
    }

    func testUnknownIsNeverProduced() {
        for line in ["", "x", "  ", "foo bar", "))", "\"", "${", "#[[", "$"] {
            XCTAssertNotEqual(intent(line), .unknown, line)
            XCTAssertNotEqual(intent(line, nodeTypes: ["some_unmapped_node"]), .unknown, line)
        }
    }

    func testCFamilyRulesAreUnchanged() {
        let recognizer = CompletionIntentRecognizer { _ in [] }
        XCTAssertEqual(
            recognizer.recognize(at: 0, prefix: "#inc", lineTextBeforeCursor: "#inc", languageId: "cpp"),
            .preprocessor
        )
        XCTAssertEqual(
            recognizer.recognize(at: 0, prefix: "x", lineTextBeforeCursor: "// x", languageId: "cpp"),
            .comment
        )
    }
}
