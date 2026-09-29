//
//  AggregatedCompletionEntry.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import SwiftUI
import CodeEditSourceEditor

/// A ``CodeSuggestionEntry`` backed by an aggregated ``CompletionCandidate``.
struct AggregatedCompletionEntry: CodeSuggestionEntry {
    /// The candidate this row was built from.
    let candidate: CompletionCandidate

    var label: String { candidate.label }
    var detail: String? { candidate.detail }
    var documentation: String? { candidate.documentation }
    var pathComponents: [String]? { nil }
    var targetPosition: CursorPosition? { nil }
    var sourcePreview: String? { nil }

    var image: Image { LSPCompletionEntry.image(for: candidate.kind) }
    var imageColor: Color { LSPCompletionEntry.color(for: candidate.kind) }
    var deprecated: Bool { candidate.deprecated }

    var badge: CodeSuggestionBadge? { CompletionPresenter.badge(for: candidate.source) }
}
