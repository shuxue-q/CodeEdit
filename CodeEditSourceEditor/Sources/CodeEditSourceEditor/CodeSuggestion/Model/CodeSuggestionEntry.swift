//
//  CodeSuggestionEntry.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 7/22/25.
//

import AppKit
import SwiftUI

/// Represents an item that can be displayed in the code suggestion view
public protocol CodeSuggestionEntry {
    var label: String { get }
    var detail: String? { get }
    var documentation: String? { get }

    /// Leave as `nil` if the link is in the same document.
    var pathComponents: [String]? { get }
    var targetPosition: CursorPosition? { get }
    var sourcePreview: String? { get }

    var image: Image { get }
    var imageColor: Color { get }

    var deprecated: Bool { get }

    /// A trailing badge identifying the source that produced this entry (snippet, keyword, AI, …).
    /// Returns `nil` by default, which draws no badge.
    var badge: CodeSuggestionBadge? { get }
}

public extension CodeSuggestionEntry {
    /// The default badge is `nil`; conformers opt in by overriding this property.
    var badge: CodeSuggestionBadge? { nil }
}
