//
//  TestsNavigatorParser.swift
//  CodeEdit
//
//  Created by CodeEdit on 22/09/2026.
//

import Foundation

/// Scans Swift source text for XCTest and swift-testing declarations.
enum TestsNavigatorParser {
    /// Parses `source` and returns the discovered test suites in source order.
    ///
    /// Detection rules:
    /// - XCTest: `class FooTests: XCTestCase`-style declarations. Any `class X: Y`
    ///   where `Y` contains "TestCase" or `X` ends with "Tests" counts as a suite.
    ///   Methods named `test…()` inside the suite body are test cases.
    /// - swift-testing: types annotated with `@Suite` are suites; functions
    ///   annotated with `@Test` (with or without arguments, possibly on a
    ///   preceding line) are test cases.
    /// - Nested types are flattened away: only top-level suites are reported and
    ///   every matching method within a suite's brace scope belongs to it.
    /// - `//` comments are ignored. A `//` inside a string literal is treated as
    ///   a comment too; this parser intentionally stays heuristic.
    ///
    /// - Parameter source: The Swift source text to scan.
    /// - Returns: Discovered suites, each with its test cases and 1-based lines.
    static func parse(source: String) -> [DiscoveredTestSuite] {
        var suites: [DiscoveredTestSuite] = []
        var activeSuite = false
        var suiteDepth = 0
        var suiteSawBrace = false
        var braceDepth = 0
        var pendingSuiteAttribute = false
        var pendingTestAttribute = false

        for (index, rawLine) in source.components(separatedBy: .newlines).enumerated() {
            let lineNumber = index + 1
            let line = stripLineComment(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if !trimmed.isEmpty {
                if trimmed.contains(suiteAttributeRegex) { pendingSuiteAttribute = true }
                if trimmed.contains(testAttributeRegex) { pendingTestAttribute = true }

                var declaredSuite = false
                if !activeSuite,
                   let name = suiteName(in: trimmed, hasSuiteAttribute: pendingSuiteAttribute) {
                    suites.append(DiscoveredTestSuite(name: name, line: lineNumber, tests: []))
                    activeSuite = true
                    suiteDepth = braceDepth
                    suiteSawBrace = false
                    pendingSuiteAttribute = false
                    declaredSuite = true
                }
                // Also checked on the suite's own declaration line so one-line
                // declarations like `@Suite struct S { @Test func t() {} }` work.
                if activeSuite,
                   let name = testName(in: trimmed, hasTestAttribute: pendingTestAttribute) {
                    suites[suites.count - 1].tests.append(DiscoveredTestCase(name: name, line: lineNumber))
                    pendingTestAttribute = false
                } else if !declaredSuite && !trimmed.hasPrefix("@") {
                    // A statement that is neither an attribute nor a declaration
                    // breaks the attribute-to-declaration association.
                    pendingSuiteAttribute = false
                    pendingTestAttribute = false
                }
                if declaredSuite { pendingTestAttribute = false }
            }

            let opens = line.filter { $0 == "{" }.count
            let closes = line.filter { $0 == "}" }.count
            if activeSuite && opens > 0 { suiteSawBrace = true }
            braceDepth += opens - closes
            if activeSuite && suiteSawBrace && braceDepth <= suiteDepth {
                activeSuite = false
            }
        }

        return suites
    }

    // MARK: - Declaration Matching

    /// `class FooTests: XCTestCase` — also matches qualified superclasses such as
    /// `XCTest.XCTestCase` and modifiers before `class` (`final`, `public`, …).
    private static let classDeclRegex = #/\bclass\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([A-Za-z_][A-Za-z0-9_.]*)/#

    /// swift-testing suite types: `struct`/`class`/`actor` following `@Suite`.
    private static let typeDeclRegex = #/\b(?:struct|class|actor)\s+([A-Za-z_][A-Za-z0-9_]*)/#

    /// XCTest test methods: `func testSomething()` / `func test_something() async throws`.
    private static let testFuncRegex = #/\bfunc\s+(test[A-Za-z0-9_]*)\s*\(/#

    /// Any function declaration, used for `@Test`-annotated functions.
    private static let anyFuncRegex = #/\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/#

    private static let suiteAttributeRegex = #/@Suite\b/#
    private static let testAttributeRegex = #/@Test\b/#

    /// Returns the suite name declared on `line`, if any.
    private static func suiteName(in line: String, hasSuiteAttribute: Bool) -> String? {
        if let match = line.firstMatch(of: classDeclRegex) {
            let name = String(match.1)
            let superclass = String(match.2)
            if superclass.contains("TestCase") || name.hasSuffix("Tests") {
                return name
            }
        }
        if hasSuiteAttribute, let match = line.firstMatch(of: typeDeclRegex) {
            return String(match.1)
        }
        return nil
    }

    /// Returns the test case name declared on `line`, if any.
    private static func testName(in line: String, hasTestAttribute: Bool) -> String? {
        if let match = line.firstMatch(of: testFuncRegex) {
            return String(match.1)
        }
        if hasTestAttribute, let match = line.firstMatch(of: anyFuncRegex) {
            return String(match.1)
        }
        return nil
    }

    /// Removes a trailing `//` comment from `line`.
    private static func stripLineComment(_ line: String) -> String {
        guard let range = line.range(of: "//") else { return line }
        return String(line[..<range.lowerBound])
    }
}
