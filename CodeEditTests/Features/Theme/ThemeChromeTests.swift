//
//  ThemeChromeTests.swift
//  CodeEditTests
//
//  Created by CodeEdit on 2026-09-29.
//

import AppKit
import Testing
@testable import CodeEdit

@Suite
@MainActor
struct ThemeChromeTests {
    private func brightness(_ color: NSColor) -> CGFloat {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
    }

    @Test
    func testDarkBackgroundSurfacesGetLighter() {
        let palette = Theme.ChromePalette(background: NSColor(hex: "#1A1B26"))
        #expect(palette.isDark)
        let canvas = brightness(palette.surface(.canvas))
        let bar = brightness(palette.surface(.bar))
        let sidebar = brightness(palette.surface(.sidebar))
        let border = brightness(palette.surface(.border))
        #expect(canvas < bar && bar < sidebar && sidebar < border)
    }

    @Test
    func testLightBackgroundSurfacesGetDarker() {
        let palette = Theme.ChromePalette(background: NSColor(hex: "#FFFFFF"))
        #expect(!palette.isDark)
        let canvas = brightness(palette.surface(.canvas))
        let bar = brightness(palette.surface(.bar))
        let sidebar = brightness(palette.surface(.sidebar))
        let border = brightness(palette.surface(.border))
        #expect(canvas > bar && bar > sidebar && sidebar > border)
    }

    @Test
    func testCanvasSurfaceIsTheThemeBackground() {
        let palette = Theme.ChromePalette(background: NSColor(hex: "#24283B"))
        #expect(palette.surface(.canvas).hexString == "#24283b")
    }

    @Test
    func testEveryBundledThemeDefinesDistinctCoreTokens() {
        for theme in ThemeModel.shared.themes where theme.isBundled {
            let tokens = theme.editor.coreTokens
            let colors = [tokens.keywords, tokens.identifiers, tokens.functions, tokens.comments].map(\.color)
            #expect(colors.allSatisfy { !$0.isEmpty }, "\(theme.displayName) has an empty core token color")
            #expect(tokens.comments.color != theme.editor.text.color, "\(theme.displayName) comments match text")
            #expect(tokens.keywords.color != tokens.functions.color, "\(theme.displayName) keywords match functions")
        }
    }

    @Test
    func testCoreTokenAliasesReadAndWriteStoredKeys() {
        guard var editor = ThemeModel.shared.themes.first?.editor else { return }
        #expect(editor.functions == editor.commands)
        #expect(editor.identifiers == editor.variables)
        editor.functions = Theme.Attributes(color: "#010203")
        editor.identifiers = Theme.Attributes(color: "#040506")
        #expect(editor.commands.color == "#010203")
        #expect(editor.variables.color == "#040506")
        #expect(editor.editorTheme.commands.color == NSColor(hex: "#010203"))
    }
}
