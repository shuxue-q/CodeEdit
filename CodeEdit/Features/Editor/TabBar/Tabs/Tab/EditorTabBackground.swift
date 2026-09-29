//
//  EditorTabBackground.swift
//  CodeEdit
//
//  Created by Austin Condiff on 1/17/23.
//

import SwiftUI

struct EditorTabBackground: View {
    /// Inset of the capsule from the tab's leading and trailing edges.
    static let horizontalInset: CGFloat = 2
    /// Inset of the capsule from the top and bottom of the tab bar row.
    static let verticalInset: CGFloat = 3

    var isActive: Bool
    var isPressing: Bool
    var isDragging: Bool
    var isHovering: Bool = false

    @Environment(\.colorScheme)
    private var colorScheme

    @ObservedObject private var themeModel: ThemeModel = .shared

    @AppSettings(\.theme.useThemeBackground)
    private var useThemeBackground

    @Environment(\.controlActiveState)
    private var activeState

    @Environment(\.isActiveEditor)
    private var isActiveEditor

    private var inHoldingState: Bool {
        isPressing || isDragging
    }

    var body: some View {
        ZStack {
            if isActive {
                // Opaque fill clips cleanly to a capsule; EffectView does not.
                if useThemeBackground, let palette = themeModel.selectedTheme?.chrome {
                    palette.activeTab
                } else {
                    Color(nsColor: .controlBackgroundColor)
                }

                // Accent color (visible if active)
                Color(.controlAccentColor)
                    .hueRotation(.degrees(-5))
                    .opacity(
                        colorScheme == .dark
                        ? activeState == .inactive ? 0.22 : inHoldingState ? 0.33 : 0.26
                        : activeState == .inactive ? 0.1 : inHoldingState ? 0.27 : 0.2
                    )
                    .saturation(isActiveEditor ? 1.0 : 0.0)
            }

            if colorScheme == .dark {
                // Highlight (if in dark mode)
                Color(.white)
                    .blendMode(.plusLighter)
                    .opacity(
                        isActive
                        ? activeState == .inactive ? 0.04 : inHoldingState ? 0.14 : 0.09
                        : isPressing || isHovering ? 0.05 : 0
                    )
            }

            if isDragging && !isActive {
                // Dragging color (if not active)
                Color(.unemphasizedSelectedTextBackgroundColor)
                    .opacity(0.85)
            }

            if !isActive && isPressing {
                Color(.unemphasizedSelectedTextBackgroundColor)
            } else if !isActive && isHovering {
                Color(.unemphasizedSelectedTextBackgroundColor)
                    .opacity(0.5)
            }
        }
        .clipShape(Capsule())
    }
}

struct EditorTabBackground_Previews: PreviewProvider {
    static var previews: some View {
        EditorTabBackground(isActive: false, isPressing: false, isDragging: false)
    }
}
