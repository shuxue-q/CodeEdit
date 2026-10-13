//
//  DartLineScannerTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/13/26.
//

import XCTest
@testable import CodeEdit

/// The Dart dialect of ``CompletionLineScanner`` and the string and comment pass of ``DartLineScanner``.
final class DartLineScannerTests: XCTestCase {
    private func tokens(_ text: String, dialect: CompletionLineScanner.Dialect = .dart) -> [String] {
        CompletionLineScanner.scan(text, dialect: dialect).tokens.map(\.text)
    }

    // MARK: - Operators

    func testNullAwareAndCascadeOperators() {
        XCTAssertEqual(tokens("a?.b"), ["a", "?.", "b"])
        XCTAssertEqual(tokens("b..add"), ["b", "..", "add"])
        XCTAssertEqual(tokens("b?..add"), ["b", "?..", "add"])
        XCTAssertEqual(tokens("  ..add(1)"), ["..", "add", "(", "1", ")"])
    }

    func testArrowAndIfNullOperators() {
        XCTAssertEqual(tokens("int f() => x"), ["int", "f", "(", ")", "=>", "x"])
        XCTAssertEqual(tokens("a ?? b"), ["a", "??", "b"])
        XCTAssertEqual(tokens("a ??= b"), ["a", "??=", "b"])
    }

    func testSpreadOperators() {
        XCTAssertEqual(tokens("[...a"), ["[", "...", "a"])
        XCTAssertEqual(tokens("[...?a"), ["[", "...?", "a"])
    }

    func testIntegerDivisionAndUnsignedShift() {
        XCTAssertEqual(tokens("a ~/ b"), ["a", "~/", "b"])
        XCTAssertEqual(tokens("a >>> b"), ["a", ">>>", "b"])
    }

    func testSingleQuotesOpenAStringInDart() {
        XCTAssertEqual(CompletionLineScanner.scan("x = 'abc", dialect: .dart).state, .string)
        XCTAssertEqual(CompletionLineScanner.scan("x = 'a", dialect: .cFamily).state, .character)
    }

    /// The C-family dialect keeps its tokens: none of Dart's operators are matched there.
    func testCFamilyTokenizationIsUnchanged() {
        XCTAssertEqual(tokens("a?.b", dialect: .cFamily), ["a", "?", ".", "b"])
        XCTAssertEqual(tokens("x..y", dialect: .cFamily), ["x", ".", ".", "y"])
        XCTAssertEqual(tokens("a => b", dialect: .cFamily), ["a", "=", ">", "b"])
        XCTAssertEqual(tokens("a ?? b", dialect: .cFamily), ["a", "?", "?", "b"])
        XCTAssertEqual(tokens("f(...)", dialect: .cFamily), ["f", "(", "...", ")"])
        XCTAssertEqual(tokens("std::vector<int> v", dialect: .cFamily), ["std", "::", "vector", "<", "int", ">", "v"])
        XCTAssertEqual(tokens("p->x", dialect: .cFamily), ["p", "->", "x"])
        XCTAssertEqual(tokens("p->x"), ["p", "-", ">", "x"], "`->` is not a Dart operator")
    }

    // MARK: - Strings and interpolation

    private func scan(_ text: String) -> DartLineScanner.Result {
        DartLineScanner.scan(text)
    }

    func testCodeWithClosedStringsReadsThemAsEmptyLiterals() {
        let result = scan("print('a${b}c', \"d\"); fo")
        XCTAssertEqual(result.state, .code)
        XCTAssertEqual(result.code, "print('', ''); fo")
        XCTAssertFalse(result.isInInterpolation)
    }

    func testOpenStrings() {
        XCTAssertEqual(scan("x = 'hello wo").state, .string)
        XCTAssertEqual(scan("x = \"hello").state, .string)
        XCTAssertEqual(scan("x = '''multi").state, .string)
        XCTAssertEqual(scan("x = '''one''' + 'two").state, .string)
        XCTAssertEqual(scan("x = '''done'''").state, .code)
        XCTAssertEqual(scan("x = 'it\\'s").state, .string, "An escaped quote does not close the string")
    }

    func testInterpolatedNames() {
        XCTAssertEqual(scan("'Hi $na").state, .interpolatedName)
        XCTAssertEqual(scan("'Hi $").state, .interpolatedName)
        XCTAssertEqual(scan("'Hi$na").state, .interpolatedName)
        XCTAssertEqual(scan("'$a and $b").state, .interpolatedName)
        XCTAssertEqual(scan("'$a and ").state, .string)
        XCTAssertEqual(scan("'cost \\$5").state, .string, "An escaped `$` is text")
        XCTAssertEqual(scan("r'$na").state, .string, "Raw strings do not interpolate")
    }

    func testCodeInsideAnInterpolation() {
        let result = scan("'Hi ${user.na")
        XCTAssertEqual(result.state, .code)
        XCTAssertEqual(result.code, "user.na")
        XCTAssertTrue(result.isInInterpolation)

        XCTAssertEqual(scan("'${m['k'].le").code, "m[''].le", "Strings nest inside an interpolation")
        XCTAssertEqual(scan("'${a} and ${b").code, "b")
        let closed = scan("'${a}' + b")
        XCTAssertEqual(closed.code, "'' + b")
        XCTAssertFalse(closed.isInInterpolation)
        XCTAssertEqual(scan("'${ {1: 2}[1]").code, " {1: 2}[1]", "A map literal's braces stay in the code")
        XCTAssertEqual(scan("'${ {1: 2}[1] } x").state, .string, "The last `}` closes the interpolation")
    }

    func testRawPrefixOnlyAfterANonWordCharacter() {
        XCTAssertEqual(scan("bar'$na").state, .interpolatedName, "`bar'` is not a raw string")
        XCTAssertEqual(scan("(r\"$na").state, .string)
    }

    // MARK: - Comments

    func testComments() {
        XCTAssertEqual(scan("// note").state, .lineComment)
        XCTAssertEqual(scan("/// Docs for").state, .lineComment)
        XCTAssertEqual(scan("x = 1; // trailing").state, .lineComment)
        XCTAssertEqual(scan("/* open").state, .blockComment)
        XCTAssertEqual(scan("/* a /* nested */ still open").state, .blockComment)
        XCTAssertEqual(scan("/* a /* nested */ closed */ fo").state, .code)
        XCTAssertEqual(scan("'http://example.com").state, .string, "`//` inside a string is text")
    }

    func testStringOpenedInsideCodeReportsTheCodeBeforeIt() {
        XCTAssertEqual(scan("import 'package:fl").code, "import ")
    }
}
