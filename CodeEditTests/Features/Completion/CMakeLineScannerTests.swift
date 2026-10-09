//
//  CMakeLineScannerTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
@testable import CodeEdit

final class CMakeLineScannerTests: XCTestCase {
    private func scan(_ text: String) -> CMakeLineScanner.Result {
        CMakeLineScanner.scan(text)
    }

    // MARK: - Comments

    func testHashStartsALineComment() {
        XCTAssertEqual(scan("# note").state, .lineComment)
        XCTAssertEqual(scan("project(x) # note").state, .lineComment)
        XCTAssertEqual(scan("set(A b#c").state, .lineComment, "A `#` ends an unquoted argument")
    }

    func testBracketCommentsOpenAndClose() {
        XCTAssertEqual(scan("#[[ open").state, .bracketComment)
        XCTAssertEqual(scan("#[=[ ]] still open").state, .bracketComment)
        XCTAssertEqual(scan("#[=[ closed ]=] set(").state, .code)
        XCTAssertEqual(scan("#[=[ closed ]=] set(").parenthesisDepth, 1)
        XCTAssertEqual(scan("#[ not a bracket").state, .lineComment)
    }

    func testSlashesAreNotComments() {
        let result = scan("add_subdirectory(// not a comment ")
        XCTAssertEqual(result.state, .code)
        XCTAssertEqual(result.parenthesisDepth, 1)
    }

    // MARK: - Quotes and brackets

    func testQuotedArguments() {
        XCTAssertEqual(scan("message(\"open").state, .quoted)
        XCTAssertEqual(scan("message(\"closed\" ").state, .code)
        XCTAssertEqual(scan("message(\"a \\\" still open").state, .quoted)
        XCTAssertEqual(scan("message(\"a # not a comment").state, .quoted)
        XCTAssertEqual(scan("message(\"a (b").parenthesisDepth, 1, "Parentheses in quotes do not count")
    }

    func testClosingQuoteAtTheEndIsReported() {
        XCTAssertTrue(scan("message(\"done\"").endsWithClosedQuote)
        XCTAssertFalse(scan("message(\"done\" ").endsWithClosedQuote)
        XCTAssertFalse(scan("message(\"done").endsWithClosedQuote)
    }

    func testBracketArguments() {
        XCTAssertEqual(scan("set(X [[open").state, .bracketArgument)
        XCTAssertEqual(scan("set(X [==[ ]] open").state, .bracketArgument)
        XCTAssertEqual(scan("set(X [[closed]] ").state, .code)
        XCTAssertEqual(scan("set(X [abc] ").state, .code, "A single bracket is an ordinary character")
        XCTAssertTrue(scan("set(X [[closed ( ]] ").parenthesisDepth == 1)
    }

    // MARK: - References

    func testOpenReferences() {
        XCTAssertEqual(scan("set(X ${").reference, .variable)
        XCTAssertEqual(scan("set(X ${CMAKE_").reference, .variable)
        XCTAssertEqual(scan("set(X $ENV{").reference, .environment)
        XCTAssertEqual(scan("set(X $CACHE{A").reference, .cache)
        XCTAssertNil(scan("set(X ${A}").reference)
        XCTAssertNil(scan("set(X $ENV").reference)
        XCTAssertNil(scan("set(X $env{").reference, "References are case sensitive")
    }

    func testNestedReferencesReportTheInnermost() {
        XCTAssertEqual(scan("${A_$ENV{").reference, .environment)
        XCTAssertEqual(scan("${A_$ENV{B}_").reference, .variable)
        XCTAssertNil(scan("${A_$ENV{B}_}").reference)
    }

    func testReferencesExpandInsideQuotes() {
        let result = scan("message(\"dir: ${CMAKE_")
        XCTAssertEqual(result.reference, .variable)
        XCTAssertEqual(result.state, .quoted)
        XCTAssertNil(scan("message(\"dir: ${CMAKE_SOURCE_DIR} ").reference)
        XCTAssertEqual(scan("message(\"dir: ${CMAKE_SOURCE_DIR} ").state, .quoted)
    }

    func testEscapedReferencesAreText() {
        XCTAssertNil(scan("message(\"\\${CMAKE_").reference)
        XCTAssertEqual(scan("message(\"\\${CMAKE_").state, .quoted)
        XCTAssertNil(scan("set(X \\${").reference)
    }

    func testAnUnquotedReferenceEndsAtWhitespace() {
        XCTAssertNil(scan("set(X ${A b").reference)
        XCTAssertEqual(scan("message(\"${A b").reference, .variable, "Quoted text may hold spaces")
    }

    // MARK: - Parentheses and code

    func testParenthesisDepth() {
        XCTAssertEqual(scan("set(").parenthesisDepth, 1)
        XCTAssertEqual(scan("if(NOT (A OR B").parenthesisDepth, 2)
        XCTAssertEqual(scan("project(x) ").parenthesisDepth, 0)
        XCTAssertEqual(scan("))").parenthesisDepth, 0, "Never negative")
        XCTAssertEqual(scan("set(A \\() ").parenthesisDepth, 0, "An escaped parenthesis does not open")
    }

    func testLastCodeCharacterAndBlankness() {
        XCTAssertEqual(scan("endif() ").lastCodeCharacter, ")")
        XCTAssertEqual(scan("endif() # note").lastCodeCharacter, ")")
        XCTAssertNil(scan("   ").lastCodeCharacter)
        XCTAssertTrue(scan("   ").isBlank)
        XCTAssertTrue(scan("").isBlank)
        XCTAssertFalse(scan("# note").isBlank)
        XCTAssertNil(scan("#[[ note ]] ").lastCodeCharacter)
    }
}
