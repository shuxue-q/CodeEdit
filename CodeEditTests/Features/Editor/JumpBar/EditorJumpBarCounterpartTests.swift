//
//  EditorJumpBarCounterpartTests.swift
//  CodeEditTests
//
//  Created by CodeEdit on 9/17/26.
//

import XCTest
@testable import CodeEdit

final class EditorJumpBarCounterpartTests: XCTestCase {
    func testHeaderMapsToSourceExtensions() {
        let counterparts = EditorJumpBarCounterpart.counterpartExtensions(for: "h")
        XCTAssertEqual(counterparts, EditorJumpBarCounterpart.sourceExtensions)
        XCTAssertTrue(EditorJumpBarCounterpart.counterpartExtensions(for: "hpp").contains("cpp"))
    }

    func testSourceMapsToHeaderExtensions() {
        let counterparts = EditorJumpBarCounterpart.counterpartExtensions(for: "cpp")
        XCTAssertEqual(counterparts, EditorJumpBarCounterpart.headerExtensions)
        XCTAssertTrue(EditorJumpBarCounterpart.counterpartExtensions(for: "m").contains("h"))
    }

    func testUnpairedExtensionHasNoCounterparts() {
        XCTAssertTrue(EditorJumpBarCounterpart.counterpartExtensions(for: "swift").isEmpty)
        XCTAssertTrue(EditorJumpBarCounterpart.counterpartExtensions(for: "txt").isEmpty)
    }

    func testCounterpartURLsFindsExistingSiblings() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("aic.cpp")
        let header = directory.appendingPathComponent("aic.h")
        let hpp = directory.appendingPathComponent("aic.hpp")
        try Data().write(to: source)
        try Data().write(to: header)
        try Data().write(to: hpp)

        let found = Set(EditorJumpBarCounterpart.counterpartURLs(for: source).map(\.lastPathComponent))
        XCTAssertEqual(found, ["aic.h", "aic.hpp"])
    }
}
