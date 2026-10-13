//
//  RustLineScannerTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/13/26.
//

import XCTest
@testable import CodeEdit

/// ``RustLineScanner`` and the Rust dialect of ``CompletionLineScanner``.
final class RustLineScannerTests: XCTestCase {
    private func state(_ line: String) -> RustLineScanner.State {
        RustLineScanner.scan(line).state
    }

    private func code(_ line: String) -> String {
        RustLineScanner.scan(line).code
    }

    private func tokens(_ text: String) -> [String] {
        CompletionLineScanner.scan(text, dialect: .rust).tokens.map(\.text)
    }

    // MARK: - Strings

    func testStrings() {
        XCTAssertEqual(state("    let s = \"hel"), .string)
        XCTAssertEqual(state("    let s = \"a\\\"b"), .string, "An escaped quote does not close")
        XCTAssertEqual(state("    let s = \"done\"; x."), .code)
        XCTAssertEqual(code("    let s = \"done\"; x."), "    let s = \"\"; x.")
    }

    func testRawStrings() {
        XCTAssertEqual(state("    let s = r\"C:\\path"), .string)
        XCTAssertEqual(state("    let s = r\"C:\\\"; x"), .code, "Raw strings have no escapes")
        XCTAssertEqual(state("    let s = r#\"say \"hi\" "), .string, "A quote without its # does not close")
        XCTAssertEqual(state("    let s = r#\"say \"hi\"\"#; v."), .code)
        XCTAssertEqual(code("    let s = r##\"a\"#b\"##; v."), "    let s = \"\"; v.")
    }

    func testByteAndCStrings() {
        XCTAssertEqual(state("    let b = b\"by"), .string)
        XCTAssertEqual(state("    let b = br#\"raw"), .string)
        XCTAssertEqual(state("    let c = c\"text"), .string)
        XCTAssertEqual(code("    let b = b\"x\"; y"), "    let b = \"\"; y")
        XCTAssertEqual(state("    let rb = crab"), .code, "A prefix that ends an identifier is not a string")
    }

    // MARK: - Characters and lifetimes

    func testCharacterLiterals() {
        XCTAssertEqual(code("    let c = 'a'; x"), "    let c = \"\"; x")
        XCTAssertEqual(code("    let c = '\\n'; x"), "    let c = \"\"; x")
        XCTAssertEqual(code("    let c = '\\''; x"), "    let c = \"\"; x")
        XCTAssertEqual(code("    let b = b'a'; x"), "    let b = \"\"; x")
        XCTAssertEqual(state("    let c = 'a"), .character, "A character literal being typed")
        XCTAssertEqual(state("    let c = '"), .character)
        XCTAssertEqual(state("    let c = '\\"), .character)
        XCTAssertEqual(state("    let b = b'"), .character)
    }

    func testLifetimes() {
        XCTAssertEqual(state("fn f<'a>(x: &'a str) -> &'a"), .code)
        XCTAssertEqual(code("fn f<'a>(x: &'a str)"), "fn f<'a>(x: &'a str)")
        XCTAssertEqual(state("fn f(x: &'"), .code, "A lifetime being typed after &")
        XCTAssertEqual(state("struct S<'a, '"), .code)
        XCTAssertEqual(state("fn f<T: '"), .code)
        XCTAssertEqual(state("    'outer: loop {"), .code, "A loop label")
        XCTAssertEqual(state("    let s: &'static str = \"x"), .string)
        XCTAssertEqual(state("    break 'ou"), .code)
    }

    // MARK: - Comments

    func testComments() {
        XCTAssertEqual(state("    // note"), .lineComment)
        XCTAssertEqual(state("/// Docs for"), .lineComment)
        XCTAssertEqual(state("//! Crate docs"), .lineComment)
        XCTAssertEqual(state("    let x = 1; // trailing"), .lineComment)
        XCTAssertEqual(state("    let s = \"// not a comment"), .string)
        XCTAssertEqual(state("    /* open"), .blockComment)
        XCTAssertEqual(state("    /* outer /* inner */ still"), .blockComment, "Block comments nest")
        XCTAssertEqual(state("    /* a /* b */ c */ x."), .code)
        XCTAssertEqual(code("    /* a /* b */ c */ x."), "      x.", "The comment reads as one space")
    }

    // MARK: - Tokens

    func testRustOperators() {
        XCTAssertEqual(tokens("a::b"), ["a", "::", "b"])
        XCTAssertEqual(tokens("f() -> T"), ["f", "(", ")", "->", "T"])
        XCTAssertEqual(tokens("Some(x) => y"), ["Some", "(", "x", ")", "=>", "y"])
        XCTAssertEqual(tokens("parse::<"), ["parse", "::<"])
        XCTAssertEqual(tokens("0..n"), ["0", "..", "n"])
        XCTAssertEqual(tokens("0..=n"), ["0", "..=", "n"])
        XCTAssertEqual(tokens("a && b || c?"), ["a", "&&", "b", "||", "c", "?"])
        XCTAssertEqual(tokens("x?."), ["x", "?", "."])
    }

    func testNumbersAndTupleFields() {
        XCTAssertEqual(tokens("let x = 1.5"), ["let", "x", "=", "1.5"])
        XCTAssertEqual(tokens("let x = 1."), ["let", "x", "=", "1."])
        XCTAssertEqual(tokens("1.max(2)"), ["1", ".", "max", "(", "2", ")"])
        XCTAssertEqual(tokens("pair.0."), ["pair", ".", "0", "."])
    }

    func testLifetimeTokens() {
        XCTAssertEqual(tokens("&'a str"), ["&", "'a", "str"])
        XCTAssertEqual(tokens("&'"), ["&", "'"])
        XCTAssertEqual(tokens("<'static>"), ["<", "'static", ">"])
    }

    func testCFamilyScanIsUnchanged() {
        XCTAssertEqual(CompletionLineScanner.scan("0..n").tokens.map(\.text), ["0.", ".", "n"])
        XCTAssertEqual(CompletionLineScanner.scan("x = 'a").state, .character)
    }
}
