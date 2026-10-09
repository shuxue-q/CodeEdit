//
//  CompletionRankerSemanticTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
import LanguageServerProtocol
@testable import CodeEdit

/// The ranker's signals that come from meaning rather than text: the expected type, the server's score,
/// and statistics per receiver type.
final class CompletionRankerSemanticTests: XCTestCase {
    private func plain(_ label: String) -> CompletionCandidate {
        CompletionCandidate(
            id: UUID().uuidString,
            label: label,
            filterText: label,
            kind: .variable,
            source: .lsp,
            payload: .plain(insertText: label)
        )
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

    // MARK: - Receiver type

    func testAMemberAcceptedOnTheSameReceiverTypeIsLifted() {
        let members = [plain("alpha"), plain("bravo")]
        let withStats = CompletionRanker.rank(
            members, prefix: "", intent: .memberAccess, receiverFrequencies: ["bravo": 20]
        ).items.map(\.label)
        XCTAssertEqual(withStats, ["bravo", "alpha"])
        // Another receiver type brings no receiver statistics: the server order stands.
        let without = CompletionRanker.rank(members, prefix: "", intent: .memberAccess).items.map(\.label)
        XCTAssertEqual(without, ["alpha", "bravo"])
    }

    func testReceiverFrequencyAddsToTheIntentFrequency() {
        let members = [plain("alpha"), plain("bravo")]
        let ranked = CompletionRanker.rank(
            members,
            prefix: "",
            intent: .memberAccess,
            intentFrequencies: ["alpha": 10],
            receiverFrequencies: ["bravo": 30],
            weights: RankingWeights(server: 0)
        ).items.map(\.label)
        XCTAssertEqual(ranked, ["bravo", "alpha"])
    }

    func testReceiverRecencyLiftsAMemberJustAcceptedOnThatType() {
        let now = Date()
        let recent = CompletionRanker.rank(
            [plain("alpha"), plain("bravo")],
            prefix: "",
            intent: .memberAccess,
            receiverLastAccepted: ["bravo": now.addingTimeInterval(-10)],
            now: now,
            weights: RankingWeights(server: 0)
        ).items.map(\.label)
        XCTAssertEqual(recent, ["bravo", "alpha"])
    }
}
