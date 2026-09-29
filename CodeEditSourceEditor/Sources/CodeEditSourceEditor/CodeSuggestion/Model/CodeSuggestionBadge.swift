//
//  CodeSuggestionBadge.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import SwiftUI

/// A small trailing badge shown on a code suggestion row, identifying which source produced it
/// (for example a snippet, a keyword, or an AI suggestion).
public struct CodeSuggestionBadge: Equatable {
    /// The glyph shown for this badge.
    public let image: Image
    /// The tint applied to the glyph.
    public let color: Color
    /// The accessibility label read for this badge.
    public let accessibilityLabel: String

    /// Creates a new badge.
    /// - Parameters:
    ///   - image: The glyph shown for this badge.
    ///   - color: The tint applied to the glyph.
    ///   - accessibilityLabel: The accessibility label read for this badge.
    public init(image: Image, color: Color, accessibilityLabel: String) {
        self.image = image
        self.color = color
        self.accessibilityLabel = accessibilityLabel
    }

    public static func == (lhs: CodeSuggestionBadge, rhs: CodeSuggestionBadge) -> Bool {
        lhs.accessibilityLabel == rhs.accessibilityLabel
    }
}
