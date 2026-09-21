//
//  XcodeCapsuleContainer.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/17/26.
//

import SwiftUI

/// A reusable capsule container replicating the Xcode 15/16 top toolbar pill styling.
struct XcodeCapsuleContainer<Content: View>: View {
    @Environment(\.colorScheme)
    private var colorScheme

    @Environment(\.controlActiveState)
    private var activeState

    let content: Content
    var height: CGFloat = 40
    var horizontalPadding: CGFloat = 8

    init(
        height: CGFloat = 40,
        horizontalPadding: CGFloat = 8,
        @ViewBuilder content: () -> Content
    ) {
        self.height = height
        self.horizontalPadding = horizontalPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .background {
                Capsule()
                    .fill(backgroundColor)
            }
            .overlay {
                Capsule()
                    .strokeBorder(borderColor, lineWidth: 0.5)
            }
            .opacity(activeState == .inactive ? 0.6 : 1.0)
    }

    private var backgroundColor: Color {
        if colorScheme == .dark {
            return Color(nsColor: .controlBackgroundColor).opacity(0.85)
        } else {
            return Color(nsColor: .windowBackgroundColor).opacity(0.95)
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
