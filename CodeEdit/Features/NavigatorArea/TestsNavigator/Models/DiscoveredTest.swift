//
//  DiscoveredTest.swift
//  CodeEdit
//
//  Created by CodeEdit on 22/09/2026.
//

import Foundation

/// A Swift source file that contains at least one discovered test suite.
struct DiscoveredTestFile: Equatable, Hashable, Identifiable, Sendable {
    var id: URL { fileURL }
    /// Absolute file URL of the source file.
    let fileURL: URL
    /// Display name of the file, including its extension.
    let fileName: String
    /// Test suites declared in the file, in source order.
    var suites: [DiscoveredTestSuite]
}

/// A test suite: an `XCTestCase` subclass or a type annotated with `@Suite`.
struct DiscoveredTestSuite: Equatable, Hashable, Identifiable, Sendable {
    /// Stable identifier derived from the suite name and its declaration line.
    var id: String { "\(name):\(line)" }
    /// Name of the suite type.
    let name: String
    /// 1-based line of the type declaration.
    let line: Int
    /// Test cases declared inside the suite body, in source order.
    var tests: [DiscoveredTestCase]
}

/// A single test case: a `test…()` method or a function annotated with `@Test`.
struct DiscoveredTestCase: Equatable, Hashable, Identifiable, Sendable {
    /// Stable identifier derived from the test name and its declaration line.
    var id: String { "\(name):\(line)" }
    /// Name of the test function, without its parameter list.
    let name: String
    /// 1-based line of the function declaration.
    let line: Int
}
