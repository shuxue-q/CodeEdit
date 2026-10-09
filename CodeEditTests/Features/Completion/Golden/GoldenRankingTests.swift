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
    private let allCases = GoldenMemberAndScopeCases.all + GoldenPositionCases.all + GoldenSemanticCases.all

    func testCaseNamesAreUnique() {
        let names = allCases.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertGreaterThanOrEqual(allCases.count, 10)
    }

    func testMemberAndScopeCases() async {
        for golden in GoldenMemberAndScopeCases.all { await check(golden) }
    }

    func testPositionCases() async {
        for golden in GoldenPositionCases.all { await check(golden) }
    }

    func testSemanticCases() async {
        for golden in GoldenSemanticCases.all { await check(golden) }
    }

    private func check(_ golden: GoldenCase) async {
        let (intent, ranked) = await golden.run()
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
