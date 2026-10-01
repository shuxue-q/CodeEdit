//
//  CompletionLineScannerTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/30/26.
//

import XCTest
@testable import CodeEdit

final class CompletionLineScannerTests: XCTestCase {
    private func texts(_ line: String) -> [String] {
        CompletionLineScanner.scan(line).tokens.map(\.text)
    }

    func testMultiCharacterOperatorsAreSingleTokens() {
        XCTAssertEqual(texts("a->b::c == d <<= 1"), ["a", "->", "b", "::", "c", "==", "d", "<<=", "1"])
    }

    func testNumbersKeepTheirDecimalPoint() {
        XCTAssertEqual(texts("x = 1.5 + 2."), ["x", "=", "1.5", "+", "2."])
    }

    func testClosedLiteralsAreOneToken() {
        let result = CompletionLineScanner.scan(#"puts("a \" b"); c = '\''; "#)
        XCTAssertEqual(result.state, .code)
        XCTAssertEqual(result.tokens.map(\.kind).filter { $0 == .literal }.count, 2)
        XCTAssertTrue(result.hasTrailingSpace)
    }

    func testOpenLiteralsAndComments() {
        XCTAssertEqual(CompletionLineScanner.scan(#"puts("abc"#).state, .string)
        XCTAssertEqual(CompletionLineScanner.scan("c = 'a").state, .character)
        XCTAssertEqual(CompletionLineScanner.scan("x; // note").state, .lineComment)
        XCTAssertEqual(CompletionLineScanner.scan("x; /* note").state, .blockComment)
        XCTAssertEqual(CompletionLineScanner.scan("x /* a */ y").state, .code)
    }

    func testLeadingAndTrailingSpace() {
        let result = CompletionLineScanner.scan("vector<int> ")
        XCTAssertEqual(result.tokens.map(\.hasLeadingSpace), [true, false, false, false])
        XCTAssertTrue(result.hasTrailingSpace)
        XCTAssertFalse(CompletionLineScanner.scan("a <").hasTrailingSpace)
        XCTAssertTrue(CompletionLineScanner.scan("a <").tokens[1].hasLeadingSpace)
    }
}
