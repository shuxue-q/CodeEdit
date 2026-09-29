//
//  MarkdownPreviewModeControl.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 28.09.26.
//

import SwiftUI

/// Source / Preview / Split control shown at the trailing end of the editor tab bar.
struct MarkdownPreviewModeControl: View {
    @ObservedObject var model: MarkdownPreviewModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MarkdownPreviewMode.allCases) { mode in
                modeButton(mode)
            }
        }
    }

    private func modeButton(_ mode: MarkdownPreviewMode) -> some View {
        let selected = model.mode == mode
        return Button {
            model.mode = mode
        } label: {
            Text(mode.title)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background {
                    if selected {
                        Capsule().fill(Color.primary.opacity(0.12))
                    }
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.primary : Color.secondary)
        .help(mode.help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
