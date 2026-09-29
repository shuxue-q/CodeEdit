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

    /// The inputs to ``score(_:prefix:options:)`` that stay constant across all candidates in a request.
    private struct ScoringOptions {
        let syntax: SyntacticContext
        let isExplicit: Bool
        let frequencies: [String: Int]
        let weights: RankingWeights
    }

    /// Filters `candidates` to those that match `prefix` and are allowed in `syntax`, then ranks
    /// and returns them, with AI candidates placed in a fixed band after the top non-AI items.
    static func rank(
        _ candidates: [CompletionCandidate],
        prefix: String,
        syntax: SyntacticContext,
        isExplicit: Bool = false,
        frequencies: [String: Int] = [:],
        weights: RankingWeights = .default
    ) -> [CompletionCandidate] {
        let normalizedPrefix = prefix.hasPrefix("#") ? String(prefix.dropFirst()) : prefix
        let ordered = orderedByServer(candidates)
        let options = ScoringOptions(syntax: syntax, isExplicit: isExplicit, frequencies: frequencies, weights: weights)
        let scored = score(ordered, prefix: normalizedPrefix, options: options)
        return assemble(scored, weights: weights)
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

    /// Computes the composite score for each candidate that survives context filtering and the
    /// fuzzy match against `prefix`.
    private static func score(
        _ ordered: [CompletionCandidate],
        prefix: String,
        options: ScoringOptions
    ) -> [ScoredCandidate] {
        let maxIndex = Double(max(ordered.count - 1, 1))
        var scored: [ScoredCandidate] = []
        for (index, candidate) in ordered.enumerated() {
            guard let contextWeight = contextWeight(
                kind: candidate.kind,
                source: candidate.source,
                syntax: options.syntax,
                isExplicit: options.isExplicit
            ) else {
                continue
            }
            let matchText = candidate.filterText.isEmpty ? candidate.label : candidate.filterText
            guard let fuzzy = FuzzyMatcher.match(pattern: prefix, candidate: matchText) else {
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
    private static func assemble(_ scored: [ScoredCandidate], weights: RankingWeights) -> [CompletionCandidate] {
        let nonAICandidates = scored
            .filter { $0.candidate.source != .ai }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.matchLength != rhs.matchLength { return lhs.matchLength < rhs.matchLength }
                return lhs.candidate.label < rhs.candidate.label
            }
            .map(\.candidate)

        let aiCandidates = scored
            .filter { $0.candidate.source == .ai }
            .sorted { $0.score > $1.score }
            .prefix(weights.aiMaxItems)
            .map(\.candidate)

        guard !aiCandidates.isEmpty else { return nonAICandidates }

        var result = nonAICandidates
        result.insert(contentsOf: aiCandidates, at: min(weights.aiInsertAfter, result.count))
        return result
    }

    /// The context weight for a candidate, or `nil` when it should be excluded in this context.
    ///
    /// `.memberAccess` boosts variables and functions and excludes snippets/keywords entirely.
    /// `.statement` boosts snippets and keywords. `.topLevel` boosts types and declaration
    /// snippets. `.preprocessor` keeps only macros, files, and include snippets. In
    /// `.comment`/`.string`, candidates are excluded unless the request was explicit.
    static func contextWeight(
        kind: LSPCompletionCategory,
        source: CompletionSource,
        syntax: SyntacticContext,
        isExplicit: Bool
    ) -> Double? {
        switch syntax {
        case .comment, .string:
            return isExplicit ? 0.1 : nil
        case .memberAccess:
            return memberAccessWeight(kind: kind, source: source)
        case .preprocessor:
            return preprocessorWeight(kind: kind, source: source)
        case .statement:
            return [.snippet, .keyword].contains(kind) ? 1.0 : 0.5
        case .topLevel:
            return Self.typeKinds.union([.snippet]).contains(kind) ? 1.0 : 0.5
        case .typePosition:
            return Self.typeKinds.contains(kind) ? 1.0 : 0.3
        case .unknown:
            return 0.5
        }
    }

    private static let typeKinds: Set<LSPCompletionCategory> = [.class, .struct, .interface, .enum, .typeAlias]

    private static func memberAccessWeight(kind: LSPCompletionCategory, source: CompletionSource) -> Double? {
        guard source != .snippet, source != .keyword else { return nil }
        return kind == .variable || kind == .function ? 1.0 : 0.4
    }

    private static func preprocessorWeight(kind: LSPCompletionCategory, source: CompletionSource) -> Double? {
        guard ![.macro, .file, .snippet].contains(kind) else { return 1.0 }
        return source == .lsp ? 0.3 : nil
    }
}
