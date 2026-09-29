//
//  FuzzyMatcher.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

/// The result of a successful fuzzy match: a relevance score and the indices in the candidate
/// string that matched the pattern, in order.
struct FuzzyMatch: Equatable {
    let score: Double
    let matchedIndices: [Int]
}

/// A case-insensitive subsequence fuzzy matcher used to filter and rank completion candidates.
enum FuzzyMatcher {
    /// Matches `pattern` against `candidate` as a case-insensitive subsequence.
    ///
    /// Bonuses are given for an exact-case match, a match at index 0, a match at a word boundary
    /// (after `_`, a camelCase hump, or a non-alphanumeric character), and consecutive runs.
    /// Gaps and leading unmatched characters are penalized. An empty pattern matches everything
    /// with a score of 0.
    /// - Parameters:
    ///   - pattern: The typed prefix.
    ///   - candidate: The text to match against.
    /// - Returns: A ``FuzzyMatch`` when `pattern` is a subsequence of `candidate`, otherwise `nil`.
    static func match(pattern: String, candidate: String) -> FuzzyMatch? {
        guard !pattern.isEmpty else { return FuzzyMatch(score: 0, matchedIndices: []) }
        guard !candidate.isEmpty else { return nil }

        let patternChars = Array(pattern)
        let candidateChars = Array(candidate)

        var score: Double = 0
        var matchedIndices: [Int] = []
        var searchIndex = 0
        var state = MatchState(index: 0, candidateChars: candidateChars, lastMatchIndex: -1, consecutiveRun: 0)

        for patternChar in patternChars {
            var matched = false
            while searchIndex < candidateChars.count {
                let candidateChar = candidateChars[searchIndex]
                guard candidateChar.lowercased() == patternChar.lowercased() else {
                    searchIndex += 1
                    continue
                }
                matched = true
                matchedIndices.append(searchIndex)
                state = MatchState(
                    index: searchIndex,
                    candidateChars: candidateChars,
                    lastMatchIndex: state.lastMatchIndex,
                    consecutiveRun: state.consecutiveRun
                )
                score += matchScore(candidateChar: candidateChar, patternChar: patternChar, state: &state)
                state = MatchState(
                    index: state.index,
                    candidateChars: candidateChars,
                    lastMatchIndex: searchIndex,
                    consecutiveRun: state.consecutiveRun
                )
                searchIndex += 1
                break
            }
            if !matched { return nil }
        }

        return FuzzyMatch(score: max(score, 0), matchedIndices: matchedIndices)
    }

    /// The running state carried between matched characters, used to score gaps and runs.
    private struct MatchState {
        let index: Int
        let candidateChars: [Character]
        let lastMatchIndex: Int
        var consecutiveRun: Int
    }

    private static func matchScore(
        candidateChar: Character,
        patternChar: Character,
        state: inout MatchState
    ) -> Double {
        let index = state.index
        var bonus: Double = 4
        if candidateChar == patternChar { bonus += 2 }
        if index == 0 { bonus += 3 }
        if index > 0, isWordBoundary(before: index, in: state.candidateChars) { bonus += 2 }

        if state.lastMatchIndex >= 0 {
            let gap = index - state.lastMatchIndex - 1
            if gap == 0 {
                state.consecutiveRun += 1
                bonus += Double(state.consecutiveRun)
            } else {
                state.consecutiveRun = 0
                bonus -= Double(gap) * 0.2
            }
        } else if index > 0 {
            bonus -= Double(index) * 0.1
        }

        return bonus
    }

    private static func isWordBoundary(before index: Int, in chars: [Character]) -> Bool {
        let previous = chars[index - 1]
        let current = chars[index]
        if previous == "_" { return true }
        if previous.isLowercase && current.isUppercase { return true }
        if !previous.isLetter && !previous.isNumber { return true }
        return false
    }
}
