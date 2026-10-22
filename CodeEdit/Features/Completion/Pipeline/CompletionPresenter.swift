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

    /// The trailing badge for a completion source: LSP, tree-sitter (AST) for snippets, keywords and
    /// postfix templates, AI, or a plain word from the document. The AI icon keeps its original colors;
    /// the others are tinted.
    static func badge(for source: CompletionSource) -> CodeSuggestionBadge? {
        switch source {
        case .lsp:
            return CodeSuggestionBadge(
                image: CompletionIconImage.template("LSP-provider"),
                color: .secondary,
                accessibilityLabel: String(localized: "Language server")
            )
        case .snippet:
            return CodeSuggestionBadge(
                image: CompletionIconImage.template("tree-sitter-ast-provider"),
                color: .teal,
                accessibilityLabel: String(localized: "Snippet")
            )
        case .keyword:
            return CodeSuggestionBadge(
                image: CompletionIconImage.template("tree-sitter-ast-provider"),
                color: .pink,
                accessibilityLabel: String(localized: "Keyword")
            )
        case .ai:
            return CodeSuggestionBadge(
                image: CompletionIconImage.original("AI-provider"),
                color: .purple,
                accessibilityLabel: String(localized: "AI suggestion")
            )
        case .postfix:
            return CodeSuggestionBadge(
                image: CompletionIconImage.template("tree-sitter-ast-provider"),
                color: .mint,
                accessibilityLabel: String(localized: "Postfix")
            )
        case .word:
            return CodeSuggestionBadge(
                image: Image(systemName: "textformat.abc"),
                color: .gray,
                accessibilityLabel: String(localized: "Word")
            )
        }
    }
}
