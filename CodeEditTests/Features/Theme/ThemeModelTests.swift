//
//  ThemeModelTests.swift
//  CodeEditTests
//
//  Created by CodeEdit on 2026-09-16.
//

import AppKit
import Foundation
import Testing
@testable import CodeEdit

@Suite
@MainActor
struct ThemeModelTests {
    @Test
    func testThemeModelInitialization() throws {
        let themeModel = ThemeModel.shared
        #expect(!themeModel.themes.isEmpty)
        #expect(themeModel.selectedDarkTheme != nil)
        #expect(themeModel.selectedLightTheme != nil)
        #expect(themeModel.selectedDarkTheme?.appearance == .dark)
        #expect(themeModel.selectedLightTheme?.appearance == .light)
    }

    @Test
    func testDarkThemeSelection() throws {
        let themeModel = ThemeModel.shared
        let darkThemes = themeModel.darkThemes
        #expect(!darkThemes.isEmpty)
        for theme in darkThemes {
            #expect(theme.appearance == .dark)
        }
    }

    @Test
    func testLightThemeSelection() throws {
        let themeModel = ThemeModel.shared
        let lightThemes = themeModel.lightThemes
        #expect(!lightThemes.isEmpty)
        for theme in lightThemes {
            #expect(theme.appearance == .light)
        }
    }

    @Test
    func testMatchAppearanceThemeSelection() throws {
        let themeModel = ThemeModel.shared
        let originalMatch = themeModel.settings.matchAppearance
        defer {
            themeModel.settings.matchAppearance = originalMatch
        }

        themeModel.settings.matchAppearance = true
        let isDark = ThemeModel.isSystemInDarkMode
        let expectedTheme = isDark ? themeModel.selectedDarkTheme : themeModel.selectedLightTheme
        #expect(themeModel.selectedTheme == expectedTheme)
    }

    @Test
    func testActivateThemePreservesOppositeAppearance() throws {
        let themeModel = ThemeModel.shared
        guard let darkTheme = themeModel.darkThemes.first,
              let lightTheme = themeModel.lightThemes.first else {
            Issue.record("Missing required dark or light bundled themes")
            return
        }

        let originalLight = themeModel.selectedLightTheme
        let originalDark = themeModel.selectedDarkTheme
        let originalSelected = themeModel.selectedTheme
        defer {
            themeModel.selectedLightTheme = originalLight
            themeModel.selectedDarkTheme = originalDark
            themeModel.selectedTheme = originalSelected
        }

        // Activate dark theme: selectedDarkTheme and selectedTheme become darkTheme,
        // but selectedLightTheme MUST NOT be mutated or corrupted.
        themeModel.activateTheme(darkTheme)
        #expect(themeModel.selectedTheme == darkTheme)
        #expect(themeModel.selectedDarkTheme == darkTheme)
        #expect(themeModel.selectedLightTheme == originalLight)

        // Activate light theme: selectedLightTheme and selectedTheme become lightTheme,
        // but selectedDarkTheme MUST NOT be mutated or corrupted.
        themeModel.activateTheme(lightTheme)
        #expect(themeModel.selectedTheme == lightTheme)
        #expect(themeModel.selectedLightTheme == lightTheme)
        #expect(themeModel.selectedDarkTheme == darkTheme)
    }

    @Test
    func testAppAppearanceOverrideInIsSystemInDarkMode() throws {
        let originalAppearance = Settings.shared.preferences.general.appAppearance
        defer {
            Settings.shared.preferences.general.appAppearance = originalAppearance
        }

        Settings.shared.preferences.general.appAppearance = .dark
        #expect(ThemeModel.isSystemInDarkMode == true)

        Settings.shared.preferences.general.appAppearance = .light
        #expect(ThemeModel.isSystemInDarkMode == false)
    }
}
