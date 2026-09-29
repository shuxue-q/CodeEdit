//
//  CodeSuggestionBadgeTests.swift
//  CodeEditSourceEditorTests
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import SwiftUI
import XCTest
@testable import CodeEditSourceEditor

final class CodeSuggestionBadgeTests: XCTestCase {
    private struct FixtureSuggestion: CodeSuggestionEntry {
        var label: String
        var detail: String?
        var documentation: String?
        var pathComponents: [String]?
        var targetPosition: CursorPosition?
        var sourcePreview: String?
        var image: Image { Image(systemName: "cube") }
        var imageColor: Color { .orange }
        var deprecated: Bool { false }
    }

    private struct BadgedSuggestion: CodeSuggestionEntry {
        var label: String
        var detail: String?
        var documentation: String?
        var pathComponents: [String]?
        var targetPosition: CursorPosition?
        var sourcePreview: String?
        var image: Image { Image(systemName: "cube") }
        var imageColor: Color { .orange }
        var deprecated: Bool { false }
        var badge: CodeSuggestionBadge? {
            CodeSuggestionBadge(
                image: Image(systemName: "sparkles"),
                color: .purple,
                accessibilityLabel: "AI suggestion"
            )
        }
    }

    func testDefaultBadgeIsNil() {
        let suggestion = FixtureSuggestion(label: "foo")
        XCTAssertNil(suggestion.badge)
    }

    func testConformerCanSupplyABadge() {
        let suggestion = BadgedSuggestion(label: "foo")
        XCTAssertEqual(suggestion.badge?.accessibilityLabel, "AI suggestion")
    }

    @MainActor
    func testLabelViewRendersWithABadge() {
        let suggestion = BadgedSuggestion(label: "for (int i = 0; i < n; ++i)")
        let view = CodeSuggestionLabelView(
            suggestion: suggestion,
            labelColor: .labelColor,
            secondaryLabelColor: .secondaryLabelColor,
            font: .systemFont(ofSize: 12)
        )
        // Rendering must not crash and the badge must still be reachable from the entry.
        _ = view.body
        XCTAssertNotNil(suggestion.badge)
    }
}
