//
//  CompletionRanker.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import Foundation

/// Fuzzy-filters and ranks deduplicated completion candidates.
enum CompletionRanker {
    /// One candidate's composite score, plus the text length it matched against for tie-breaking.
    private struct ScoredCandidate {
        let candidate: CompletionCandidate
        let score: Double
        let matchLength: Int
    }

    /// The inputs to ``score(_:options:)`` that stay constant across all candidates in a request.
    private struct ScoringOptions {
        let intent: CompletionIntent
        let prefix: String
        let isExplicit: Bool
        let frequencies: [String: Int]
        let weights: RankingWeights
    }

    /// Filters `candidates` to those that match `prefix` and are allowed for `intent`, then ranks
    /// them, with AI candidates placed in a fixed band after the top non-AI items, and decides
    /// whether the top item is a strong enough match to be preselected.
    static func rank(
        _ candidates: [CompletionCandidate],
        prefix: String,
        intent: CompletionIntent,
        isExplicit: Bool = false,
        frequencies: [String: Int] = [:],
        weights: RankingWeights = .default
    ) -> RankedCompletions {
        let normalizedPrefix = prefix.hasPrefix("#") ? String(prefix.dropFirst()) : prefix
        let ordered = orderedByServer(candidates)
        let options = ScoringOptions(
            intent: intent,
            prefix: normalizedPrefix,
            isExplicit: isExplicit,
            frequencies: frequencies,
            weights: weights
        )
        let scored = score(ordered, options: options)
        return assemble(scored, prefix: normalizedPrefix, weights: weights)
    }

    /// Normalizes the server's ordering: sorts by `sortText` (falling back to `label`), keeping
    /// the original relative order for ties.
    private static func orderedByServer(_ candidates: [CompletionCandidate]) -> [CompletionCandidate] {
        candidates.enumerated().sorted { lhs, rhs in
            let lhsKey = lhs.element.sortText ?? lhs.element.label
            let rhsKey = rhs.element.sortText ?? rhs.element.label
            if lhsKey != rhsKey { return lhsKey < rhsKey }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Computes the composite score for each candidate that survives intent filtering and the
    /// fuzzy match against the typed prefix.
    private static func score(
        _ ordered: [CompletionCandidate],
        options: ScoringOptions
    ) -> [ScoredCandidate] {
        let maxIndex = Double(max(ordered.count - 1, 1))
        var scored: [ScoredCandidate] = []
        for (index, candidate) in ordered.enumerated() {
            guard let intentWeight = CompletionIntentPolicy.weight(
                kind: candidate.kind,
                source: candidate.source,
                intent: options.intent,
                isExplicit: options.isExplicit
            ) else {
                continue
            }
            let contextWeight = intentWeight
                + CompletionIntentPolicy.prefixShapeBonus(kind: candidate.kind, prefix: options.prefix)
            let matchText = candidate.filterText.isEmpty ? candidate.label : candidate.filterText
            guard let fuzzy = FuzzyMatcher.match(pattern: options.prefix, candidate: matchText) else {
                continue
            }
            let serverRank = 1.0 - Double(index) / maxIndex
            let blendedServerRank = candidate.score.map { (serverRank + $0) / 2 } ?? serverRank
            let key = CompletionDeduplicator.normalizedLabel(candidate.label)
            let frequency = Double(options.frequencies[key] ?? 0)

            let weights = options.weights
            let total = weights.fuzzy * fuzzy.score
                + weights.server * blendedServerRank
                + weights.context * contextWeight
                + weights.frequency * log1p(frequency)

            scored.append(ScoredCandidate(candidate: candidate, score: total, matchLength: matchText.count))
        }
        return scored
    }

    /// Sorts non-AI candidates by score (ties broken by match length, then label), then inserts
    /// the top-scoring AI candidates into a fixed band after `weights.aiInsertAfter` items.
    private static func assemble(
        _ scored: [ScoredCandidate],
        prefix: String,
        weights: RankingWeights
    ) -> RankedCompletions {
        let sortedNonAI = scored
            .filter { $0.candidate.source != .ai }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.matchLength != rhs.matchLength { return lhs.matchLength < rhs.matchLength }
                return lhs.candidate.label < rhs.candidate.label
            }
        let nonAICandidates = sortedNonAI.map(\.candidate)
        let preselected = isStrongBestMatch(sortedNonAI, prefix: prefix, weights: weights) ? 0 : nil

        let aiCandidates = scored
            .filter { $0.candidate.source == .ai }
            .sorted { $0.score > $1.score }
            .prefix(weights.aiMaxItems)
            .map(\.candidate)

        guard !aiCandidates.isEmpty else {
            return RankedCompletions(items: nonAICandidates, preselectedIndex: preselected)
        }

        var result = nonAICandidates
        result.insert(contentsOf: aiCandidates, at: min(weights.aiInsertAfter, result.count))
        // The best non-AI item stays first: the AI band is inserted after `aiInsertAfter` (>= 1) items.
        return RankedCompletions(items: result, preselectedIndex: preselected)
    }

    /// Whether the top-ranked item deserves to be preselected: the server marked it, it beats the
    /// runner-up by `weights.preselectMargin`, or it alone starts with the typed `prefix` (case-sensitive).
    private static func isStrongBestMatch(
        _ sortedNonAI: [ScoredCandidate],
        prefix: String,
        weights: RankingWeights
    ) -> Bool {
        guard let top = sortedNonAI.first else { return false }
        if case .lsp(let item) = top.candidate.payload, item.preselect == true {
            return true
        }
        guard sortedNonAI.count > 1 else { return true }
        let second = sortedNonAI[1]
        if top.score - second.score >= weights.preselectMargin {
            return true
        }
        guard !prefix.isEmpty else { return false }
        return startsWithCaseSensitively(top.candidate, prefix: prefix)
            && !startsWithCaseSensitively(second.candidate, prefix: prefix)
    }

    private static func startsWithCaseSensitively(_ candidate: CompletionCandidate, prefix: String) -> Bool {
        CompletionDeduplicator.normalizedLabel(candidate.label).hasPrefix(prefix)
    }
}
