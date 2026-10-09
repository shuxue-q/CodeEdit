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
        let languageId: String
        let prefix: String
        let isExplicit: Bool
        let frequencies: [String: Int]
        let intentFrequencies: [String: Int]
        let lastAccepted: [String: Date]
        let receiverFrequencies: [String: Int]
        let receiverLastAccepted: [String: Date]
        let documentIdentifiers: Set<String>
        let expectedType: TypeText?
        /// The highest server `score` among the candidates, which scales the others into `0...1`.
        let maxServerScore: Double
        let now: Date
        let weights: RankingWeights
    }

    /// Filters `candidates` to those that match `prefix` and are allowed for `intent`, then ranks
    /// them, with AI candidates placed in a fixed band after the top non-AI items, and decides
    /// whether the top item is a strong enough match to be preselected.
    static func rank(
        _ candidates: [CompletionCandidate],
        prefix: String,
        intent: CompletionIntent,
        languageId: String = "",
        isExplicit: Bool = false,
        frequencies: [String: Int] = [:],
        intentFrequencies: [String: Int] = [:],
        lastAccepted: [String: Date] = [:],
        receiverFrequencies: [String: Int] = [:],
        receiverLastAccepted: [String: Date] = [:],
        documentIdentifiers: Set<String> = [],
        expectedType: TypeText? = nil,
        now: Date = Date(),
        weights: RankingWeights = .default
    ) -> RankedCompletions {
        let normalizedPrefix = prefix.hasPrefix("#") ? String(prefix.dropFirst()) : prefix
        let ordered = orderedByServer(candidates)
        let options = ScoringOptions(
            intent: intent,
            languageId: languageId,
            prefix: normalizedPrefix,
            isExplicit: isExplicit,
            frequencies: frequencies,
            intentFrequencies: intentFrequencies,
            lastAccepted: lastAccepted,
            receiverFrequencies: receiverFrequencies,
            receiverLastAccepted: receiverLastAccepted,
            documentIdentifiers: documentIdentifiers,
            expectedType: expectedType,
            maxServerScore: ordered.compactMap(\.score).max() ?? 0,
            now: now,
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
                isExplicit: options.isExplicit,
                languageId: options.languageId
            ) else {
                continue
            }
            let contextWeight = intentWeight
                + CompletionIntentPolicy.prefixShapeBonus(
                    kind: candidate.kind,
                    prefix: options.prefix,
                    intent: options.intent
                )
            let matchText = candidate.filterText.isEmpty ? candidate.label : candidate.filterText
            guard let fuzzy = FuzzyMatcher.match(pattern: options.prefix, candidate: matchText) else {
                continue
            }
            let serverSignal = serverSignal(of: candidate, index: index, maxIndex: maxIndex, options: options)
            let key = CompletionDeduplicator.normalizedLabel(candidate.label)
            let weights = options.weights
            let total = weights.fuzzy * fuzzy.score
                + weights.server * serverSignal
                + weights.context * contextWeight
                + weights.frequency * log1p(frequency(of: key, options: options))
                + weights.recency * recencyBonus(of: key, options: options)
                + weights.proximity * proximityBonus(of: candidate, options: options)
                + typeBonus(of: candidate, options: options)
                + postfixBonus(of: candidate, options: options)

            scored.append(ScoredCandidate(candidate: candidate, score: total, matchLength: matchText.count))
        }
        return scored
    }

    /// The server's opinion of `candidate`, in `0...1`.
    ///
    /// A server that sends a relevance `score` (clangd does) is trusted for it: the candidate's score
    /// relative to the best score of the request. Without one, the position in the server's
    /// `sortText` order stands in for it.
    private static func serverSignal(
        of candidate: CompletionCandidate,
        index: Int,
        maxIndex: Double,
        options: ScoringOptions
    ) -> Double {
        if let score = candidate.score, options.maxServerScore > 0 {
            return min(1, max(0, score / options.maxServerScore))
        }
        return 1.0 - Double(index) / maxIndex
    }

    /// A postfix template typed out in full (`expr.if`) beats the members that merely match `if`.
    private static func postfixBonus(of candidate: CompletionCandidate, options: ScoringOptions) -> Double {
        guard candidate.source == .postfix, !options.prefix.isEmpty, candidate.label == options.prefix else {
            return 0
        }
        return options.weights.postfixExact
    }

    /// The expected-type bonus: full for a candidate of the expected type, partial for one that
    /// converts to it, nothing otherwise (a candidate of another type is never penalized).
    private static func typeBonus(of candidate: CompletionCandidate, options: ScoringOptions) -> Double {
        guard let expected = options.expectedType,
              let type = CandidateTypeParser.resultType(of: candidate) else {
            return 0
        }
        switch expected.match(type, candidateIsEnumerator: candidate.kind == .enumMember) {
        case .exact: return options.weights.expectedType
        case .convertible: return options.weights.convertibleType
        case .none: return 0
        }
    }

    /// Acceptances of `key` in this intent, plus those in the language's other intents at half weight,
    /// plus those on a receiver of the same type (member access), which count for that type only.
    ///
    /// The per-language table counts every intent, so the part not already counted for this intent
    /// is the fallback that keeps data recorded before intents were tracked useful.
    private static func frequency(of key: String, options: ScoringOptions) -> Double {
        let inIntent = Double(options.intentFrequencies[key] ?? 0)
        let inLanguage = Double(options.frequencies[key] ?? 0)
        let onReceiver = Double(options.receiverFrequencies[key] ?? 0)
        return onReceiver + inIntent + 0.5 * max(0, inLanguage - inIntent)
    }

    /// `1` right after accepting `key` in this intent (or on this receiver type), falling off
    /// exponentially with the age of that acceptance; `0` when it was never accepted.
    private static func recencyBonus(of key: String, options: ScoringOptions) -> Double {
        let accepted = [options.lastAccepted[key], options.receiverLastAccepted[key]].compactMap { $0 }
        guard let last = accepted.max() else { return 0 }
        let age = max(0, options.now.timeIntervalSince(last))
        return exp(-age / options.weights.recencyTimeConstant)
    }

    /// `1` when the document already contains a symbol named like `candidate`.
    private static func proximityBonus(of candidate: CompletionCandidate, options: ScoringOptions) -> Double {
        let name = CompletionDeduplicator.symbolName(of: candidate.label)
        return options.documentIdentifiers.contains(name) ? 1 : 0
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
