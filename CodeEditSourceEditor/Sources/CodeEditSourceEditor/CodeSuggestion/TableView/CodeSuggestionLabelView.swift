//
//  CodeSuggestionLabelView.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 7/24/25.
//

import AppKit
import SwiftUI

struct CodeSuggestionLabelView: View {
    let suggestion: CodeSuggestionEntry
    let labelColor: NSColor
    let secondaryLabelColor: NSColor
    let font: NSFont
    /// Puts `detail` on the trailing edge instead of directly after the name.
    var showsTrailingDetail: Bool = false
    /// White label text, used on the accent selection of the inline layout.
    var isSelected: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            suggestion.image
                .font(.system(size: font.pointSize + 2))
                .foregroundStyle(suggestion.deprecated ? .gray : suggestion.imageColor)
                .frame(width: max(font.pointSize + 4, 18), alignment: .center)

            if showsTrailingDetail {
                Text(suggestion.label)
                    .foregroundStyle(primaryColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 12)
                if let detail = trailingDetail {
                    Text(detail)
                        .foregroundStyle(secondaryColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                }
            } else {
                // Main label. One line so a row cannot grow to the height of the window.
                HStack(spacing: font.charWidth) {
                    Text(suggestion.label)
                        .foregroundStyle(suggestion.deprecated ? Color(secondaryLabelColor) : Color(labelColor))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let detail = suggestion.detail {
                        Text(detail)
                            .foregroundStyle(Color(secondaryLabelColor))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
            }

            if suggestion.deprecated {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: font.pointSize + 2))
                    .foregroundStyle(Color(labelColor), Color(secondaryLabelColor))
            }

            badgeView
        }
        .font(Font(font))
        .padding(.vertical, 3)
        .padding(.horizontal, 13)
        .buttonStyle(PlainButtonStyle())
    }

    /// The trailing source badge, in a fixed-width column so labels stay aligned across rows.
    @ViewBuilder private var badgeView: some View {
        HStack {
            if let badge = suggestion.badge {
                badge.image
                    .font(.system(size: font.pointSize))
                    .foregroundStyle(isSelected ? Color.white : badge.color)
                    .accessibilityLabel(badge.accessibilityLabel)
            }
        }
        .frame(width: max(font.pointSize + 4, 18), alignment: .center)
    }

    private var trailingDetail: String? {
        guard let detail = suggestion.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !detail.isEmpty,
              detail != suggestion.label else {
            return nil
        }
        return detail
    }

    private var primaryColor: Color {
        showsTrailingDetail && isSelected ? .white : Color(labelColor)
    }

    private var secondaryColor: Color {
        showsTrailingDetail && isSelected ? Color.white.opacity(0.85) : Color(secondaryLabelColor)
    }
}
