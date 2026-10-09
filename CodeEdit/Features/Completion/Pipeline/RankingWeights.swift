//
//  RankingWeights.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

/// Weights used by ``CompletionRanker`` to combine fuzzy, server, context, frequency, recency,
/// proximity, and expected-type signals into one composite score. Kept as a struct so tests can pin specific values.
struct RankingWeights: Equatable {
    /// Weight applied to the fuzzy-match score.
    var fuzzy: Double = 1.0
    /// Weight applied to the server's own signal: its `score` when it sends one, otherwise the
    /// position of the item in the server's `sortText` order.
    var server: Double = 0.6
    /// Weight applied to the syntactic-context weight.
    var context: Double = 0.8
    /// Weight applied to `log1p(frequency)`.
    var frequency: Double = 0.3
    /// Weight applied to the recency of the last acceptance: `exp(-age / recencyTimeConstant)`.
    var recency: Double = 0.4
    /// How long it takes the recency bonus to fall to 1/e, in seconds (30 minutes).
    var recencyTimeConstant: Double = 30 * 60
    /// Bonus for a candidate whose name already occurs in the current document.
    var proximity: Double = 0.5
    /// Bonus for a candidate whose type is the type the slot expects.
    var expectedType: Double = 1.2
    /// Bonus for a candidate whose type converts implicitly to the type the slot expects.
    var convertibleType: Double = 0.5
    /// Bonus for a postfix template whose label is exactly what was typed after the `.`, which lifts
    /// it over the members that merely match.
    var postfixExact: Double = 2.0
    /// The most AI candidates shown per completion list.
    var aiMaxItems: Int = 3
    /// How many non-AI items are shown before the AI band, so AI never buries exact matches.
    var aiInsertAfter: Int = 2
    /// How far the top candidate's score must beat the runner-up's for it to be preselected.
    var preselectMargin: Double = 1.5

    /// The default production weights.
    static let `default` = RankingWeights()
}
