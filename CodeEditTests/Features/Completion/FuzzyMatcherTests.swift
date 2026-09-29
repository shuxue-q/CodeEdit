//
//  FuzzyMatcherTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import XCTest
@testable import CodeEdit

final class FuzzyMatcherTests: XCTestCase {
    func testEmptyPatternMatchesEverythingWithZeroScore() {
        let match = FuzzyMatcher.match(pattern: "", candidate: "anything")
        XCTAssertEqual(match, FuzzyMatch(score: 0, matchedIndices: []))
    }

    func testNonSubsequenceDoesNotMatch() {
        XCTAssertNil(FuzzyMatcher.match(pattern: "xyz", candidate: "printf"))
    }

    func testCaseInsensitiveSubsequenceMatches() {
        XCTAssertNotNil(FuzzyMatcher.match(pattern: "PF", candidate: "printf"))
    }

    func testLeadingMatchOutranksLaterMatch() throws {
        // "pf" should score printf (p at index 0) higher than fprintf (p at index 1).
        let printfScore = try XCTUnwrap(FuzzyMatcher.match(pattern: "pf", candidate: "printf")).score
        let fprintfScore = try XCTUnwrap(FuzzyMatcher.match(pattern: "pf", candidate: "fprintf")).score
        XCTAssertGreaterThan(printfScore, fprintfScore)
    }

    func testCamelCaseHumpIsAWordBoundaryBonus() throws {
        // "gcc" as a subsequence of "getCurrentContext" hits three humps; a run of unrelated
        // characters of the same length should score lower.
        let humps = try XCTUnwrap(FuzzyMatcher.match(pattern: "gcc", candidate: "getCurrentContext")).score
        let noHumps = try XCTUnwrap(FuzzyMatcher.match(pattern: "gcc", candidate: "gxxcxxxxxxxxxxxxc")).score
        XCTAssertGreaterThan(humps, noHumps)
    }

    func testConsecutiveMatchesOutrankScatteredOnes() throws {
        let consecutive = try XCTUnwrap(FuzzyMatcher.match(pattern: "abc", candidate: "abcdef")).score
        let scattered = try XCTUnwrap(FuzzyMatcher.match(pattern: "abc", candidate: "a1b2c3")).score
        XCTAssertGreaterThan(consecutive, scattered)
    }

    func testHashPrefixIsHandledByTheCaller() {
        // FuzzyMatcher itself is prefix-agnostic; the "#" stripping happens in CompletionRanker.
        XCTAssertNotNil(FuzzyMatcher.match(pattern: "inc", candidate: "include"))
    }
}
