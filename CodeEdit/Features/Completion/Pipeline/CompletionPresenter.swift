//
//  CompletionPresenter.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import SwiftUI
import CodeEditSourceEditor

/// Maps ranked completion candidates to the rows the suggestion window displays.
enum CompletionPresenter {
    /// Wraps each candidate as an ``AggregatedCompletionEntry``, preserving order.
    static func present(_ candidates: [CompletionCandidate]) -> [AggregatedCompletionEntry] {
        candidates.map(AggregatedCompletionEntry.init)
    }

    /// The trailing badge for a completion source: LSP, tree-sitter (AST) for snippets and keywords,
    /// or AI. The AI icon keeps its original colors; the others are tinted.
    static func badge(for source: CompletionSource) -> CodeSuggestionBadge? {
        switch source {
        case .lsp:
            return CodeSuggestionBadge(
                image: CompletionIconImage.template("LSP-provider"),
                color: .secondary,
                accessibilityLabel: "Language server"
            )
        case .snippet:
            return CodeSuggestionBadge(
                image: CompletionIconImage.template("tree-sitter-ast-provider"),
                color: .teal,
                accessibilityLabel: "Snippet"
            )
        case .keyword:
            return CodeSuggestionBadge(
                image: CompletionIconImage.template("tree-sitter-ast-provider"),
                color: .pink,
                accessibilityLabel: "Keyword"
            )
        case .ai:
            return CodeSuggestionBadge(
                image: CompletionIconImage.original("AI-provider"),
                color: .purple,
                accessibilityLabel: "AI suggestion"
            )
        }
    }
}
