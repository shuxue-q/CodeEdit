//
//  XcodeAssistantButton.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/17/26.
//

import SwiftUI

/// Assistant button with speech bubble and plus icon, featuring Xcode's gradient stroke styling.
struct XcodeAssistantButton: View {
    @Environment(\.colorScheme)
    private var colorScheme

    @Environment(\.controlActiveState)
    private var activeState

    @State private var isHovered: Bool = false

    private let iconGradient = LinearGradient(
        colors: [
            Color.orange,
            Color.pink,
            Color.purple,
            Color.blue
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        Button {
            NSApp.sendAction(#selector(CodeEditWindowController.openCommandPalette(_:)), to: nil, from: nil)
        } label: {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 36, height: 36)

                Circle()
                    .strokeBorder(borderColor, lineWidth: 0.5)
                    .frame(width: 36, height: 36)

                Image(systemName: "plus.bubble")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(iconGradient)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .opacity(activeState == .inactive ? 0.6 : 1.0)
        .help("Command Palette")
    }

    private var backgroundColor: Color {
        if colorScheme == .dark {
            return Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.95 : 0.85)
        } else {
            return Color(nsColor: .windowBackgroundColor).opacity(isHovered ? 1.0 : 0.95)
        }
    }

    private var borderColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.12)
        } else {
            return Color.black.opacity(0.08)
        }
    }
}
