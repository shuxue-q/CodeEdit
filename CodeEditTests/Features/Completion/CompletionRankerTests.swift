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

// MARK: - History and proximity signals

extension CompletionRankerTests {
    private func plain(_ label: String) -> CompletionCandidate {
        CompletionCandidate(
            id: label, label: label, filterText: label, kind: .variable, source: .lsp,
            payload: .plain(insertText: label)
        )
    }

    /// Ranks `alpha` and `bravo` with the server's ordering switched off, so they tie on every signal
    /// but the ones passed in and sort alphabetically.
    private func rankPair(
        frequencies: [String: Int] = [:],
        intentFrequencies: [String: Int] = [:],
        lastAccepted: [String: Date] = [:],
        documentIdentifiers: Set<String> = [],
        now: Date = Date()
    ) -> [String] {
        CompletionRanker.rank(
            [plain("alpha"), plain("bravo")],
            prefix: "",
            intent: .unknown,
            frequencies: frequencies,
            intentFrequencies: intentFrequencies,
            lastAccepted: lastAccepted,
            documentIdentifiers: documentIdentifiers,
            now: now,
            weights: RankingWeights(server: 0)
        ).items.map(\.label)
    }

    func testRecentAcceptanceLiftsACandidate() {
        let now = Date()
        XCTAssertEqual(rankPair(), ["alpha", "bravo"])
        XCTAssertEqual(rankPair(lastAccepted: ["bravo": now.addingTimeInterval(-60)], now: now), ["bravo", "alpha"])
    }

    func testRecencyFadesWithAge() {
        let now = Date()
        let weights = RankingWeights()
        let fresh = weights.recency * exp(-60 / weights.recencyTimeConstant)
        let old = weights.recency * exp(-6 * 3_600 / weights.recencyTimeConstant)
        XCTAssertGreaterThan(fresh, 0.3)
        XCTAssertLessThan(old, 0.001)
        // A minute-old acceptance beats a six-hour-old one, whichever candidate it was.
        XCTAssertEqual(
            rankPair(
                lastAccepted: ["alpha": now.addingTimeInterval(-60), "bravo": now.addingTimeInterval(-6 * 3_600)],
                now: now
            ),
            ["alpha", "bravo"]
        )
        XCTAssertEqual(
            rankPair(
                lastAccepted: ["alpha": now.addingTimeInterval(-6 * 3_600), "bravo": now.addingTimeInterval(-60)],
                now: now
            ),
            ["bravo", "alpha"]
        )
    }

    func testSymbolsUsedInTheDocumentAreLifted() {
        XCTAssertEqual(rankPair(documentIdentifiers: ["bravo"]), ["bravo", "alpha"])
        XCTAssertEqual(rankPair(documentIdentifiers: ["gamma"]), ["alpha", "bravo"])
    }

    func testIdentifierMatchIgnoresTheSignatureInTheLabel() {
        let ranked = CompletionRanker.rank(
            [plain("alpha(int)"), plain("bravo(int)")],
            prefix: "",
            intent: .unknown,
            documentIdentifiers: ["bravo"],
            weights: RankingWeights(server: 0)
        ).items.map(\.label)
        XCTAssertEqual(ranked, ["bravo(int)", "alpha(int)"])
    }

    func testIntentFrequencyCountsFullAndOtherIntentsCountHalf() {
        // Same total in the language table; "bravo" was accepted in this intent, "alpha" elsewhere.
        XCTAssertEqual(
            rankPair(frequencies: ["alpha": 10, "bravo": 10], intentFrequencies: ["bravo": 10]),
            ["bravo", "alpha"]
        )
        // Counts from other intents still help when nothing was recorded for this one.
        XCTAssertEqual(rankPair(frequencies: ["bravo": 10]), ["bravo", "alpha"])
    }

    // MARK: - Expected type

    private func typed(
        _ label: String,
        detail: String?,
        kind: LSPCompletionCategory = .variable,
        sortText: String? = nil
    ) -> CompletionCandidate {
        CompletionCandidate(
            id: label,
            label: label,
            filterText: label,
            sortText: sortText ?? label,
            kind: kind,
            source: .lsp,
            detail: detail,
            payload: .plain(insertText: label)
        )
    }

    private func rankTyped(_ candidates: [CompletionCandidate], expected: String?) -> [String] {
        CompletionRanker.rank(
            candidates,
            prefix: "",
            intent: .expression,
            expectedType: expected.flatMap(TypeText.parse)
        ).items.map(\.label)
    }

    func testExpectedTypeLiftsACandidateOfThatType() {
        let candidates = [typed("alpha", detail: "int"), typed("bravo", detail: "std::string")]
        XCTAssertEqual(rankTyped(candidates, expected: nil), ["alpha", "bravo"])
        XCTAssertEqual(rankTyped(candidates, expected: "std::string"), ["bravo", "alpha"])
    }

    func testClangdsSpellingOfTheExpectedTypeIsRecognized() {
        let candidates = [typed("alpha", detail: "int"), typed("bravo", detail: "basic_string<char>")]
        XCTAssertEqual(rankTyped(candidates, expected: "const std::string &"), ["bravo", "alpha"])
    }

    func testAConvertibleTypeIsLiftedLessThanAnExactOne() {
        let candidates = [
            typed("alpha", detail: "char *"), typed("bravo", detail: "int"), typed("charlie", detail: "double")
        ]
        // Exact (double) beats convertible (int), and both beat an unrelated type.
        XCTAssertEqual(rankTyped(candidates, expected: "double"), ["charlie", "bravo", "alpha"])
    }

    func testAnUnrelatedTypeIsNeverPenalized() {
        // "alpha" has an unrelated type; "bravo" has no known type. The server order must stay.
        let candidates = [typed("alpha", detail: "Foo"), typed("bravo", detail: nil)]
        XCTAssertEqual(rankTyped(candidates, expected: "std::string"), ["alpha", "bravo"])
    }

    func testTypesAreNotLiftedWhereAValueIsExpected() {
        let candidates = [
            typed("alpha", detail: nil, kind: .function), typed("bravo", detail: "std::string", kind: .class)
        ]
        XCTAssertEqual(rankTyped(candidates, expected: "std::string"), ["alpha", "bravo"])
    }

    func testTheExpectedTypeBonusIsScaledByItsWeight() {
        let candidates = [typed("alpha", detail: "int"), typed("bravo", detail: "std::string")]
        let ranked = CompletionRanker.rank(
            candidates,
            prefix: "",
            intent: .expression,
            expectedType: TypeText.parse("std::string"),
            weights: RankingWeights(expectedType: 0)
        ).items.map(\.label)
        XCTAssertEqual(ranked, ["alpha", "bravo"])
    }

    func testAnExactTypeMatchOutweighsTheServersOrderOfAFewPlaces() {
        let candidates = (0..<6).map { typed("item\($0)", detail: $0 == 5 ? "Wanted" : "Other") }
        XCTAssertEqual(rankTyped(candidates, expected: "Wanted").first, "item5")
    }

    // MARK: - Server score

    private func scored(_ label: String, score: Double?, sortText: String) -> CompletionCandidate {
        var candidate = typed(label, detail: nil, sortText: sortText)
        candidate.score = score
        return candidate
    }

    func testServerScoreIsTheServerSignalNotAHalfBlendWithTheIndex() {
        // "alphaa" is first in the server's order, "alpha" second, but both carry the same score.
        // With the score as the signal they tie and the shorter match wins; the old half-and-half blend
        // still let the index favor "alphaa".
        let candidates = [
            scored("alphaa", score: 1.0, sortText: "1"), scored("alpha", score: 1.0, sortText: "2")
        ]
        let ranked = CompletionRanker.rank(candidates, prefix: "alph", intent: .unknown).items.map(\.label)
        XCTAssertEqual(ranked, ["alpha", "alphaa"])
    }

    func testAHigherServerScoreWinsEvenAgainstTheServersSortOrder() {
        let candidates = [
            scored("alpha1", score: 0.9, sortText: "1"), scored("alpha2", score: 1.8, sortText: "2")
        ]
        let ranked = CompletionRanker.rank(candidates, prefix: "alpha", intent: .unknown).items.map(\.label)
        XCTAssertEqual(ranked, ["alpha2", "alpha1"])
    }

    func testServerScoresAreRelativeToTheBestScoreOfTheRequest() {
        // clangd's scores are not bounded by 1; only their ratio matters.
        let small = [scored("alpha1", score: 0.2, sortText: "2"), scored("alpha2", score: 0.4, sortText: "1")]
        let large = [scored("alpha1", score: 20, sortText: "2"), scored("alpha2", score: 40, sortText: "1")]
        let first = CompletionRanker.rank(small, prefix: "alpha", intent: .unknown).items.map(\.label)
        let second = CompletionRanker.rank(large, prefix: "alpha", intent: .unknown).items.map(\.label)
        XCTAssertEqual(first, second)
    }

    func testCandidatesWithoutAScoreFallBackToTheServerOrder() {
        let candidates = [
            scored("alpha1", score: nil, sortText: "1"), scored("alpha2", score: nil, sortText: "2")
        ]
        let ranked = CompletionRanker.rank(candidates, prefix: "alpha", intent: .unknown).items.map(\.label)
        XCTAssertEqual(ranked, ["alpha1", "alpha2"])
    }
}
