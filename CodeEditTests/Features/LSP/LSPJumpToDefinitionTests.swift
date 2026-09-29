//
//  LSPJumpToDefinitionTests.swift
//  CodeEditTests
//
//  Created by CodeEdit on 9/21/26.
//

import XCTest
import LanguageServerProtocol

@testable import CodeEdit

final class LSPJumpToDefinitionTests: XCTestCase {
    private func makeRange(_ line: Int, _ character: Int) -> LSPRange {
        LSPRange(
            start: Position(line: line, character: character),
            end: Position(line: line, character: character + 5)
        )
    }

    func testNilResponseProducesNoLocations() {
        let locations = LSPJumpToDefinitionDelegate.locations(
            from: nil as ThreeTypeOption<Location, [Location], [LocationLink]>?
        )
        XCTAssertTrue(locations.isEmpty)
    }

    func testSingleLocationResponse() {
        let response = ThreeTypeOption<Location, [Location], [LocationLink]>.optionA(
            Location(uri: "file:///project/a.hpp", range: makeRange(10, 2))
        )
        let locations = LSPJumpToDefinitionDelegate.locations(from: response)
        XCTAssertEqual(locations.count, 1)
        XCTAssertEqual(locations[0].uri, "file:///project/a.hpp")
        XCTAssertEqual(locations[0].range.start.line, 10)
        XCTAssertEqual(locations[0].range.start.character, 2)
    }

    func testLocationArrayResponseDeduplicates() {
        let first = Location(uri: "file:///project/a.hpp", range: makeRange(10, 2))
        let duplicate = Location(uri: "file:///project/a.hpp", range: makeRange(10, 2))
        let other = Location(uri: "file:///project/b.hpp", range: makeRange(3, 0))
        let response = ThreeTypeOption<Location, [Location], [LocationLink]>.optionB([first, duplicate, other])
        let locations = LSPJumpToDefinitionDelegate.locations(from: response)
        XCTAssertEqual(locations.count, 2)
        XCTAssertEqual(locations[0].uri, "file:///project/a.hpp")
        XCTAssertEqual(locations[1].uri, "file:///project/b.hpp")
    }

    func testLocationLinkResponseUsesTargetSelectionRange() {
        let link = LocationLink(
            originSelectionRange: makeRange(40, 7),
            targetUri: "file:///project/error.hpp",
            targetRange: makeRange(0, 0),
            targetSelectionRange: makeRange(12, 6)
        )
        let response = ThreeTypeOption<Location, [Location], [LocationLink]>.optionC([link])
        let locations = LSPJumpToDefinitionDelegate.locations(from: response)
        XCTAssertEqual(locations.count, 1)
        XCTAssertEqual(locations[0].uri, "file:///project/error.hpp")
        XCTAssertEqual(locations[0].range.start.line, 12)
        XCTAssertEqual(locations[0].range.start.character, 6)
    }
}
