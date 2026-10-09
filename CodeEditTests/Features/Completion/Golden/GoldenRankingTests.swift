//
//  GoldenRankingTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
@testable import CodeEdit

/// Runs every ``GoldenCase`` through the intent recognizer and the ranker.
final class GoldenRankingTests: XCTestCase {
    private let allCases = GoldenMemberAndScopeCases.all + GoldenPositionCases.all

    func testCaseNamesAreUnique() {
        let names = allCases.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertGreaterThanOrEqual(allCases.count, 10)
    }

    func testMemberAndScopeCases() {
        GoldenMemberAndScopeCases.all.forEach(check)
    }

    func testPositionCases() {
        GoldenPositionCases.all.forEach(check)
    }

    private func check(_ golden: GoldenCase) {
        let (intent, ranked) = golden.run()
        XCTAssertEqual(intent, golden.expectedIntent, "[\(golden.name)] intent")

        let labels = ranked.items.map(\.label)
        XCTAssertEqual(
            Array(labels.prefix(golden.expectedTop.count)),
            golden.expectedTop,
            "[\(golden.name)] top rows, full list: \(labels)"
        )

        let preselection = ranked.preselectedIndex.map { GoldenCase.Preselection.label(labels[$0]) } ?? .none
        XCTAssertEqual(preselection, golden.expectedPreselection, "[\(golden.name)] preselection")
    }
}
