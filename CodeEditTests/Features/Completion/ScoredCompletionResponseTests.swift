//
//  ScoredCompletionResponseTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
@testable import CodeEdit

final class ScoredCompletionResponseTests: XCTestCase {
    private func decode(_ json: String) throws -> ScoredCompletionResponse {
        try JSONDecoder().decode(ScoredCompletionResponse.self, from: Data(json.utf8))
    }

    func testListResponseKeepsTheScoreOfEachItem() throws {
        let response = try decode("""
        {"isIncomplete": false, "items": [
          {"label": " count", "kind": 6, "detail": "int", "score": 1.75, "sortText": "40200134count"},
          {"label": " name", "kind": 5, "detail": "std::string"}
        ]}
        """)
        XCTAssertEqual(response.items.map(\.label), [" count", " name"])
        XCTAssertEqual(response.items.first?.detail, "int")
        XCTAssertEqual(response.scores, [1.75, nil])
    }

    func testBareArrayResponseIsDecodedToo() throws {
        let response = try decode(#"[{"label": "a", "score": 0.5}, {"label": "b", "score": 2}]"#)
        XCTAssertEqual(response.items.map(\.label), ["a", "b"])
        XCTAssertEqual(response.scores, [0.5, 2])
    }

    func testNullResponseIsEmpty() throws {
        let response = try decode("null")
        XCTAssertTrue(response.items.isEmpty)
        XCTAssertTrue(response.scores.isEmpty)
    }
}
