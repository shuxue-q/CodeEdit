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
    /// An identifier taken from the current document, offered when no better source has it.
    case word
    /// A C/C++ postfix template (`expr.if`, `expr.fori`, …) that rewrites the expression before the `.`.
    case postfix

    /// Priority used by ``CompletionDeduplicator`` to pick a winner among exact duplicates.
    /// Higher wins: `lsp > snippet > postfix > keyword > ai > word`.
    var priority: Int {
        switch self {
        case .lsp: return 4
        case .snippet: return 3
        case .postfix: return 2
        case .keyword: return 1
        case .ai: return 0
        case .word: return -1
        }
    }
}
