//
//  Theme+Chrome.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/29/26.
//

import SwiftUI

extension Theme {
    /// Surfaces and borders for the window chrome, derived from ``EditorColors/background``.
    ///
    /// Every color is a step from the theme background toward its contrast color (white for a dark
    /// background, black for a light one), so the chrome always reads as part of the same theme.
    struct ChromePalette: Equatable {
        /// How far each surface moves from the theme background toward the contrast color.
        enum Step: CGFloat {
            /// The editor canvas itself.
            case canvas = 0
            /// The tab bar and breadcrumb bar.
            case bar = 0.02
            /// The navigator and status bar.
            case sidebar = 0.04
            /// Hairline dividers and borders.
            case border = 0.14
        }

        /// The theme background the palette was derived from.
        let base: NSColor
        /// Whether ``base`` is dark, judged by luminance rather than the theme's declared type.
        let isDark: Bool

        /// The theme's own text color, or nil to derive one from the background.
        let textBase: NSColor?

        /// Creates a palette from a theme background color.
        /// - Parameters:
        ///   - background: The theme's editor background.
        ///   - text: The theme's editor text color, used for chrome labels.
        init(background: NSColor, text: NSColor? = nil) {
            self.textBase = text?.usingColorSpace(.sRGB) ?? text
            let resolved = background.usingColorSpace(.sRGB) ?? background
            self.base = resolved
            let luminance = 0.299 * resolved.redComponent
                + 0.587 * resolved.greenComponent
                + 0.114 * resolved.blueComponent
            self.isDark = luminance < 0.5
        }

        /// The color a surface moves toward: white on dark backgrounds, black on light ones.
        var contrast: NSColor { isDark ? .white : .black }

        /// The theme background shifted by `step` toward ``contrast``.
        /// - Parameter step: How far to shift.
        /// - Returns: An opaque color.
        func surface(_ step: Step) -> NSColor {
            guard step != .canvas else { return base }
            return base.blended(withFraction: step.rawValue, of: contrast) ?? base
        }

        /// The theme's text color, or a stand-in derived from the background.
        private var fullText: NSColor {
            textBase ?? (base.blended(withFraction: 0.72, of: contrast) ?? contrast)
        }
        /// Primary chrome label color: the theme text at 75% over the background, deliberately subdued.
        var primaryText: NSColor { fullText.blended(withFraction: 0.25, of: base) ?? fullText }
        /// Secondary chrome label color: the theme text at 50% over the background.
        var secondaryText: NSColor { fullText.blended(withFraction: 0.5, of: base) ?? fullText }
        /// Label color for inactive tabs: the theme text at 70% over the background, legible but below the active tab.
        var tabInactiveText: Color {
            Color(nsColor: fullText.blended(withFraction: 0.3, of: base) ?? fullText)
        }
        /// Primary chrome label color for SwiftUI.
        var text: Color { Color(nsColor: primaryText) }
        /// Secondary chrome label color for SwiftUI.
        var textSecondary: Color { Color(nsColor: secondaryText) }

        /// The fill for the tab bar and breadcrumb bar.
        var bar: Color { Color(nsColor: surface(.bar)) }
        /// The fill for the navigator and status bar.
        var sidebar: Color { Color(nsColor: surface(.sidebar)) }
        /// The color for hairline dividers and borders.
        var border: Color { Color(nsColor: surface(.border)) }
        /// The fill for the active tab: the canvas color, so the tab merges into the editor below it.
        var activeTab: Color { Color(nsColor: surface(.canvas)) }
    }

    /// The window chrome palette for this theme.
    var chrome: ChromePalette {
        ChromePalette(background: editor.background.nsColor, text: editor.text.nsColor)
    }
}

extension ThemeModel {
    /// The selected theme's chrome palette, or nil when "Use theme background" is off.
    var activeChrome: Theme.ChromePalette? {
        guard Settings[\.theme].useThemeBackground else { return nil }
        return selectedTheme?.chrome
    }

    /// Primary label color for navigator, tab and breadcrumb text.
    var chromeLabelColor: NSColor { activeChrome?.primaryText ?? .labelColor }
    /// Secondary label color for navigator, tab and breadcrumb text.
    var chromeSecondaryLabelColor: NSColor { activeChrome?.secondaryText ?? .secondaryLabelColor }
}

extension Theme.EditorColors {
    /// The four token categories every theme must define: keywords, identifiers, functions and comments.
    struct CoreTokens: Equatable {
        /// Language keywords (`if`, `func`, `return`).
        let keywords: Theme.Attributes
        /// Variable and property names.
        let identifiers: Theme.Attributes
        /// Function and method names, and calls to them.
        let functions: Theme.Attributes
        /// Line and block comments.
        let comments: Theme.Attributes
    }

    /// Identifier color. Stored under `variables` in theme files.
    var identifiers: Theme.Attributes {
        get { variables }
        set { variables = newValue }
    }

    /// Function and method color. Stored under `commands` in theme files.
    var functions: Theme.Attributes {
        get { commands }
        set { commands = newValue }
    }

    /// The standardized syntax token group, read from the stored keys.
    var coreTokens: CoreTokens {
        CoreTokens(keywords: keywords, identifiers: variables, functions: commands, comments: comments)
    }
}

/// Applies the selected theme's muted chrome text colors to the hierarchical foreground styles
/// (`.primary`, `.secondary`, `.tertiary`) of everything inside the view.
private struct ThemedChromeText: ViewModifier {
    @ObservedObject private var themeModel: ThemeModel = .shared

    @AppSettings(\.theme.useThemeBackground)
    private var useThemeBackground

    func body(content: Content) -> some View {
        if useThemeBackground, let palette = themeModel.selectedTheme?.chrome {
            content.foregroundStyle(palette.text, palette.textSecondary, palette.textSecondary.opacity(0.7))
        } else {
            content.foregroundStyle(.primary, .secondary, .tertiary)
        }
    }
}

extension View {
    /// Recolors `.primary` / `.secondary` foreground styles inside the view from the theme's chrome palette.
    func themedChromeText() -> some View {
        modifier(ThemedChromeText())
    }
}
