//
//  RankingWeights.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

/// Weights used by ``CompletionRanker`` to combine fuzzy, server, context, and frequency signals
/// into one composite score. Kept as a struct so tests can pin specific values.
struct RankingWeights: Equatable {
    /// Weight applied to the fuzzy-match score.
    var fuzzy: Double = 1.0
    /// Weight applied to the server's own ordering (`sortText`/index, blended with a server score).
    var server: Double = 0.6
    /// Weight applied to the syntactic-context weight.
    var context: Double = 0.8
    /// Weight applied to `log1p(frequency)`.
    var frequency: Double = 0.3
    /// The most AI candidates shown per completion list.
    var aiMaxItems: Int = 3
    /// How many non-AI items are shown before the AI band, so AI never buries exact matches.
    var aiInsertAfter: Int = 2

    /// The default production weights.
    static let `default` = RankingWeights()
}
