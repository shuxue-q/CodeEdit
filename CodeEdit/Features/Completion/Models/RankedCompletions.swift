//
//  RankedCompletions.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

/// The output of ``CompletionRanker``: the ordered list and which row, if any, to preselect.
struct RankedCompletions {
    /// The candidates, best first.
    var items: [CompletionCandidate]
    /// The row to highlight in bold because it is a strong best match, or `nil` when no candidate
    /// stands out and the popup should just highlight the first row.
    var preselectedIndex: Int?
}
