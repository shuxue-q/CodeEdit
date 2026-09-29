//
//  CompletionSource.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

/// The origin of a completion candidate. Determines dedup priority and the row's trailing badge.
enum CompletionSource: String, Equatable, Hashable, Sendable, CaseIterable {
    case lsp
    case snippet
    case keyword
    // swiftlint:disable:next identifier_name
    case ai

    /// Priority used by ``CompletionDeduplicator`` to pick a winner among exact duplicates.
    /// Higher wins: `lsp > snippet > keyword > ai`.
    var priority: Int {
        switch self {
        case .lsp: return 3
        case .snippet: return 2
        case .keyword: return 1
        case .ai: return 0
        }
    }
}
