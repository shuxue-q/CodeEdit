//
//  CompletionRankerTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import XCTest
import LanguageServerProtocol
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
        let ranked = CompletionRanker.rank(candidates, prefix: "", intent: .unknown).items
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
        ).items
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
        let ranked = CompletionRanker.rank(candidates, prefix: "", intent: .memberAccess).items
        XCTAssertEqual(ranked.map(\.label), ["member"])
    }

    func testCommentContextExcludesEverythingUnlessExplicit() {
        let candidates = [lspCandidate(label: "member")]
        XCTAssertTrue(CompletionRanker.rank(candidates, prefix: "", intent: .comment).items.isEmpty)
        XCTAssertFalse(
            CompletionRanker.rank(candidates, prefix: "", intent: .comment, isExplicit: true).items.isEmpty
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
        let ranked = CompletionRanker.rank(candidates, prefix: "", intent: .unknown, weights: weights).items
        XCTAssertEqual(ranked.count, 3, "Only one AI candidate should survive the aiMaxItems cap")
        XCTAssertEqual(ranked[1].source, .ai, "The AI band must sit after aiInsertAfter non-AI items")
    }

    func testNonMatchingPrefixExcludesACandidate() {
        let candidates = [lspCandidate(label: "printf")]
        XCTAssertTrue(CompletionRanker.rank(candidates, prefix: "zzz", intent: .unknown).items.isEmpty)
    }

    // MARK: - Preselection

    private func lspItemCandidate(label: String, preselect: Bool? = nil) -> CompletionCandidate {
        CompletionCandidate(
            id: UUID().uuidString,
            label: label,
            filterText: label,
            kind: .variable,
            source: .lsp,
            payload: .lsp(CompletionItem(label: label, preselect: preselect))
        )
    }

    /// Margin large enough that only the other preselection rules can apply.
    private let noMargin = RankingWeights(preselectMargin: 1_000)

    func testServerPreselectFlagPreselectsTheTopItem() {
        let candidates = [lspItemCandidate(label: "foo1", preselect: true), lspItemCandidate(label: "foo2")]
        let ranked = CompletionRanker.rank(candidates, prefix: "foo", intent: .unknown, weights: noMargin)
        XCTAssertEqual(ranked.preselectedIndex, 0)
    }

    func testClearLeadOverTheRunnerUpPreselects() {
        let candidates = [lspItemCandidate(label: "foo1"), lspItemCandidate(label: "foo2")]
        let ranked = CompletionRanker.rank(
            candidates,
            prefix: "foo",
            intent: .unknown,
            frequencies: ["foo2": 500],
            weights: RankingWeights(preselectMargin: 1.0)
        )
        XCTAssertEqual(ranked.items.first?.label, "foo2")
        XCTAssertEqual(ranked.preselectedIndex, 0)
    }

    func testCloseScoresDoNotPreselect() {
        let candidates = [lspItemCandidate(label: "foo1"), lspItemCandidate(label: "foo2")]
        let ranked = CompletionRanker.rank(candidates, prefix: "foo", intent: .unknown, weights: noMargin)
        XCTAssertNil(ranked.preselectedIndex)
    }

    func testOnlyTheTopItemStartingWithTheTypedPrefixPreselects() {
        let candidates = [lspItemCandidate(label: "fooBar"), lspItemCandidate(label: "xfoo")]
        let ranked = CompletionRanker.rank(candidates, prefix: "foo", intent: .unknown, weights: noMargin)
        XCTAssertEqual(ranked.items.first?.label, "fooBar")
        XCTAssertEqual(ranked.preselectedIndex, 0)
    }

    func testPrefixMatchIsCaseSensitive() {
        let candidates = [lspItemCandidate(label: "Foo"), lspItemCandidate(label: "xfoo")]
        let ranked = CompletionRanker.rank(candidates, prefix: "foo", intent: .unknown, weights: noMargin)
        XCTAssertNil(ranked.preselectedIndex)
    }

    func testASingleCandidateIsPreselectedAndNoCandidatesPreselectNothing() {
        let single = CompletionRanker.rank([lspItemCandidate(label: "only")], prefix: "", intent: .unknown)
        XCTAssertEqual(single.preselectedIndex, 0)
        let none = CompletionRanker.rank([], prefix: "", intent: .unknown)
        XCTAssertNil(none.preselectedIndex)
    }

    func testTheAIBandNeverTakesThePreselection() {
        let candidates = [
            lspItemCandidate(label: "foo1", preselect: true),
            lspItemCandidate(label: "foo2"),
            lspItemCandidate(label: "foo3"),
            aiCandidate(label: "fooAI")
        ]
        let ranked = CompletionRanker.rank(candidates, prefix: "foo", intent: .unknown, weights: noMargin)
        XCTAssertEqual(ranked.items.first?.label, "foo1")
        XCTAssertEqual(ranked.preselectedIndex, 0)
        XCTAssertEqual(ranked.items[2].label, "fooAI", "AI band stays after two non-AI items")
    }
}
