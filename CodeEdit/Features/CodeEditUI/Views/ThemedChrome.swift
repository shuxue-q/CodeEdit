//
//  ThemedChrome.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/29/26.
//

import SwiftUI

/// Which piece of window chrome a ``View/themedChrome(_:)`` background is for.
enum ThemedChromeSurface {
    /// The navigator and status bar.
    case sidebar
    /// The tab bar and breadcrumb bar.
    case bar
}

/// Fills a view with a surface derived from the selected theme's background.
///
/// Observes ``ThemeModel`` directly, so the fill changes in the same update that changes
/// ``ThemeModel/selectedTheme``. When "Use theme background" is off, or no theme is selected,
/// it falls back to the system `fallback` material.
private struct ThemedChromeBackground: ViewModifier {
    let surface: ThemedChromeSurface
    let fallback: NSVisualEffectView.Material

    @ObservedObject private var themeModel: ThemeModel = .shared

    @AppSettings(\.theme.useThemeBackground)
    private var useThemeBackground

    func body(content: Content) -> some View {
        content.background {
            if useThemeBackground, let palette = themeModel.selectedTheme?.chrome {
                (surface == .sidebar ? palette.sidebar : palette.bar)
            } else {
                EffectView(fallback)
            }
        }
    }
}

/// A hairline divider colored from the selected theme's chrome border.
struct ThemedChromeDivider: View {
    @ObservedObject private var themeModel: ThemeModel = .shared

    @AppSettings(\.theme.useThemeBackground)
    private var useThemeBackground

    var body: some View {
        if useThemeBackground, let palette = themeModel.selectedTheme?.chrome {
            Rectangle().fill(palette.border).frame(height: 1)
        } else {
            Divider()
        }
    }
}

extension View {
    /// Backs the view with a chrome surface derived from the selected theme's background.
    /// - Parameters:
    ///   - surface: The chrome piece being filled.
    ///   - fallback: The system material used when theme backgrounds are off.
    func themedChrome(
        _ surface: ThemedChromeSurface,
        fallback: NSVisualEffectView.Material = .headerView
    ) -> some View {
        modifier(ThemedChromeBackground(surface: surface, fallback: fallback))
    }
}
