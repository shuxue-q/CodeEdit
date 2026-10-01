//
//  CompletionRankerTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import XCTest
@testable import CodeEdit

final class CompletionRankerTests: XCTestCase {
    private func lspCandidate(
        label: String,
        kind: LSPCompletionCategory = .variable,
        sortText: String? = nil
    ) -> CompletionCandidate {
        CompletionCandidate(
            id: UUID().uuidString,
            label: label,
            filterText: label,
            sortText: sortText,
            kind: kind,
            source: .lsp,
            payload: .plain(insertText: label)
        )
    }

    private func aiCandidate(label: String) -> CompletionCandidate {
        CompletionCandidate(
            id: UUID().uuidString,
            label: label,
            filterText: label,
            kind: .snippet,
            source: .ai,
            payload: .plain(insertText: label)
        )
    }

    func testSortTextOrderIsPreservedWhenOtherSignalsAreEqual() {
        let candidates = [
            lspCandidate(label: "beta", sortText: "2"),
            lspCandidate(label: "alpha", sortText: "1")
        ]
        let ranked = CompletionRanker.rank(candidates, prefix: "", intent: .unknown)
        XCTAssertEqual(ranked.map(\.label), ["alpha", "beta"])
    }

    func testFrequencyLiftsAPreviouslyAcceptedCandidate() {
        let candidates = [
            lspCandidate(label: "aaa"),
            lspCandidate(label: "aab")
        ]
        let ranked = CompletionRanker.rank(
            candidates,
            prefix: "aa",
            intent: .unknown,
            frequencies: ["aab": 50]
        )
        XCTAssertEqual(ranked.first?.label, "aab")
    }

    func testMemberAccessContextExcludesSnippetsAndKeywords() {
        let candidates = [
            lspCandidate(label: "member", kind: .variable),
            CompletionCandidate(
                id: UUID().uuidString, label: "for", filterText: "for",
                kind: .snippet, source: .snippet, payload: .snippet(body: "for")
            )
        ]
        let ranked = CompletionRanker.rank(candidates, prefix: "", intent: .memberAccess)
        XCTAssertEqual(ranked.map(\.label), ["member"])
    }

    func testCommentContextExcludesEverythingUnlessExplicit() {
        let candidates = [lspCandidate(label: "member")]
        XCTAssertTrue(CompletionRanker.rank(candidates, prefix: "", intent: .comment).isEmpty)
        XCTAssertFalse(
            CompletionRanker.rank(candidates, prefix: "", intent: .comment, isExplicit: true).isEmpty
        )
    }

    func testAIBandIsPlacedAfterTheTopNonAIItemsAndCapped() {
        var weights = RankingWeights.default
        weights.aiInsertAfter = 1
        weights.aiMaxItems = 1
        let candidates = [
            lspCandidate(label: "first"),
            lspCandidate(label: "second"),
            aiCandidate(label: "ai-one"),
            aiCandidate(label: "ai-two")
        ]
        let ranked = CompletionRanker.rank(candidates, prefix: "", intent: .unknown, weights: weights)
        XCTAssertEqual(ranked.count, 3, "Only one AI candidate should survive the aiMaxItems cap")
        XCTAssertEqual(ranked[1].source, .ai, "The AI band must sit after aiInsertAfter non-AI items")
    }

    func testNonMatchingPrefixExcludesACandidate() {
        let candidates = [lspCandidate(label: "printf")]
        XCTAssertTrue(CompletionRanker.rank(candidates, prefix: "zzz", intent: .unknown).isEmpty)
    }
}
