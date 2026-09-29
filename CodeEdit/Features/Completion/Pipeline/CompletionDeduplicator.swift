//
//  CompletionDeduplicator.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

/// Merges duplicate completion candidates gathered from several providers.
enum CompletionDeduplicator {
    /// Deduplicates `candidates`, preserving the order groups first appear in.
    ///
    /// Candidates are grouped by their normalized label. When a group contains a `.snippet`-kind
    /// candidate, plain/keyword candidates in that group are dropped. Remaining exact duplicates
    /// (same label and kind) are collapsed to the one with the highest-priority source
    /// (`lsp > snippet > keyword > ai`); the other sources are recorded in `mergedSources`.
    static func deduplicate(_ candidates: [CompletionCandidate]) -> [CompletionCandidate] {
        var order: [String] = []
        var groups: [String: [CompletionCandidate]] = [:]
        for candidate in candidates {
            let key = normalizedLabel(candidate.label)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(candidate)
        }

        var result: [CompletionCandidate] = []
        for key in order {
            guard let group = groups[key] else { continue }
            result.append(contentsOf: resolve(group: group))
        }
        return result
    }

    /// Strips whitespace and clangd's include-insertion marker (`•`) so labels compare cleanly.
    static func normalizedLabel(_ label: String) -> String {
        var trimmed = label.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("•") {
            trimmed.removeFirst()
        }
        return trimmed.trimmingCharacters(in: .whitespaces)
    }

    private static func resolve(group: [CompletionCandidate]) -> [CompletionCandidate] {
        var working = group
        let hasSnippet = working.contains { $0.kind == .snippet }
        if hasSnippet {
            working = working.filter { $0.kind == .snippet || !isKeywordOrPlain($0) }
        }
        guard !working.isEmpty else { return [] }

        var kindOrder: [LSPCompletionCategory] = []
        var byKind: [LSPCompletionCategory: [CompletionCandidate]] = [:]
        for candidate in working {
            if byKind[candidate.kind] == nil { kindOrder.append(candidate.kind) }
            byKind[candidate.kind, default: []].append(candidate)
        }

        return kindOrder.compactMap { kind in
            guard let items = byKind[kind] else { return nil }
            let sorted = items.sorted { $0.source.priority > $1.source.priority }
            guard var winner = sorted.first else { return nil }
            winner.mergedSources = Set(sorted.map { $0.source })
            return winner
        }
    }

    /// Plain-text fallbacks: local keywords, AI/plain inserts, and server items of keyword or text
    /// kind (clangd sends `for`, `while`, ... as plain keywords).
    private static func isKeywordOrPlain(_ candidate: CompletionCandidate) -> Bool {
        if candidate.source == .keyword || candidate.kind == .keyword || candidate.kind == .text { return true }
        if case .plain = candidate.payload { return true }
        return false
    }
}
