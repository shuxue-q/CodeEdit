//
//  LSPHoverTriggerTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/17/26.
//

import XCTest
@testable import CodeEdit

final class LSPHoverTriggerTests: XCTestCase {
    func testShouldRequestHoverOnIdentifiers() {
        assertHover("foo", at: 0)
        assertHover("foo", at: 2)
        assertHover("_priv", at: 0)
        assertHover("$foo", at: 0)
        assertHover("foo.h", at: 3)
        assertHover("foo.h", at: 4)
        assertHover("solver.cpp", at: 6)
    }

    func testShouldNotRequestHoverOnWhitespaceOrPunctuation() {
        XCTAssertFalse(LSPHoverTrigger.shouldRequestHover(at: 0, in: "   "))
        XCTAssertFalse(LSPHoverTrigger.shouldRequestHover(at: 0, in: "\n"))
        XCTAssertFalse(LSPHoverTrigger.shouldRequestHover(at: 3, in: "foo bar"))
        XCTAssertFalse(LSPHoverTrigger.shouldRequestHover(at: 0, in: ";"))
        XCTAssertFalse(LSPHoverTrigger.shouldRequestHover(at: 0, in: "{"))
        XCTAssertFalse(LSPHoverTrigger.shouldRequestHover(at: 0, in: "}"))
        XCTAssertFalse(LSPHoverTrigger.shouldRequestHover(at: 0, in: "("))
        XCTAssertFalse(LSPHoverTrigger.shouldRequestHover(at: 0, in: ")"))
        XCTAssertFalse(LSPHoverTrigger.shouldRequestHover(at: 0, in: " "))
    }

    func testShouldNotRequestHoverOutsideString() {
        XCTAssertFalse(LSPHoverTrigger.shouldRequestHover(at: -1, in: "foo"))
        XCTAssertFalse(LSPHoverTrigger.shouldRequestHover(at: 3, in: "foo"))
        XCTAssertFalse(LSPHoverTrigger.shouldRequestHover(at: 0, in: ""))
    }

    func testGlyphContainsMouse() {
        let glyph = NSRect(x: 10, y: 10, width: 8, height: 14)
        XCTAssertTrue(LSPHoverTrigger.glyphContainsMouse(point: NSPoint(x: 12, y: 16), glyphRect: glyph))
        XCTAssertFalse(LSPHoverTrigger.glyphContainsMouse(point: NSPoint(x: 40, y: 16), glyphRect: glyph))
        XCTAssertFalse(LSPHoverTrigger.glyphContainsMouse(point: NSPoint(x: 12, y: 40), glyphRect: glyph))
    }

    private func assertHover(_ text: String, at offset: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            LSPHoverTrigger.shouldRequestHover(at: offset, in: text as NSString),
            "expected hover at offset \(offset) in \(text)",
            file: file,
            line: line
        )
    }
}
