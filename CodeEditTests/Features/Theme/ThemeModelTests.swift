//
//  ThemeModelTests.swift
//  CodeEditTests
//
//  Created by CodeEdit on 2026-09-16.
//

import AppKit
import Foundation
import SwiftUI
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
    func testChooseThemeSwitchesAppAppearanceToMatchTheme() {
        let themeModel = ThemeModel.shared
        guard let darkTheme = themeModel.darkThemes.first,
              let lightTheme = themeModel.lightThemes.first else {
            Issue.record("Missing required dark or light bundled themes")
            return
        }
        let originalAppearance = Settings.shared.preferences.general.appAppearance
        let originalTheme = themeModel.selectedTheme
        let originalLight = themeModel.selectedLightTheme
        let originalDark = themeModel.selectedDarkTheme
        defer {
            Settings.shared.preferences.general.appAppearance = originalAppearance
            originalAppearance.applyAppearance()
            themeModel.selectedLightTheme = originalLight
            themeModel.selectedDarkTheme = originalDark
            themeModel.selectedTheme = originalTheme
        }

        Settings.shared.preferences.general.appAppearance = .light
        SettingsData.Appearances.light.applyAppearance()
        themeModel.chooseTheme(darkTheme)
        #expect(Settings.shared.preferences.general.appAppearance == .dark)
        #expect(NSApp.appearance?.name == .darkAqua)

        themeModel.chooseTheme(lightTheme)
        #expect(Settings.shared.preferences.general.appAppearance == .light)
        #expect(NSApp.appearance?.name == .aqua)
    }

    @Test
    func testBundledTokyoNightAndOneDarkProThemesLoad() {
        let themes = ThemeModel.shared.themes
        struct Expectation {
            let name: String
            let type: Theme.ThemeType
            let background: String
        }
        let expected = [
            Expectation(name: "Tokyo Night", type: .dark, background: "#1A1B26"),
            Expectation(name: "Tokyo Night Storm", type: .dark, background: "#24283B"),
            Expectation(name: "Tokyo Night Day", type: .light, background: "#E1E2E7"),
            Expectation(name: "One Dark Pro", type: .dark, background: "#282C34"),
            Expectation(name: "One Dark Pro Darker", type: .dark, background: "#23272E")
        ]
        for item in expected {
            let theme = themes.first { $0.displayName == item.name }
            #expect(theme != nil, "Missing bundled theme \(item.name)")
            #expect(theme?.appearance == item.type)
            #expect(theme?.editor.background.color == item.background)
        }
        let oneDark = themes.first { $0.displayName == "One Dark Pro" }
        #expect(oneDark?.editor.commands.color == "#61AFEF")
        #expect(oneDark?.editor.variables.color != oneDark?.editor.commands.color)
        let darker = themes.first { $0.displayName == "One Dark Pro Darker" }
        #expect(darker?.editor.commands.color == "#61AFEF")
        #expect(darker?.editor.functions.color == "#61AFEF")
        #expect(darker?.editor.variables.color == "#E06C75")
        #expect(darker?.editor.assignedVariables.color == "#56B6C2")
        #expect(darker?.editor.keywords.color == "#C678DD")
        #expect(darker?.editor.strings.color == "#98C379")
        #expect(darker?.editor.types.color == "#E5C07B")
    }

    /// The two reworked bundled themes give every syntax role the user reads code by its own color, and their
    /// terminal palettes are built from the same editor tokens.
    @Test
    func reworkedBundledThemesSeparateRolesAndSyncTerminal() throws {
        let themes = ThemeModel.shared.themes
        for name in ["One Dark Pro Darker", "Qt Creator Light"] {
            let theme = try #require(themes.first { $0.displayName == name }, "Missing bundled theme \(name)")
            let editor = theme.editor
            let roles: [(String, Theme.Attributes)] = [
                ("functions", editor.functions),
                ("variables", editor.variables),
                ("assignedVariables", editor.assignedVariables),
                ("values", editor.values),
                ("numbers", editor.numbers),
                ("operators", editor.operators),
                ("keywords", editor.keywords),
                ("text", editor.text)
            ]
            for (index, lhs) in roles.enumerated() {
                for rhs in roles[(index + 1)...] {
                    #expect(lhs.1 != rhs.1, "\(name): \(lhs.0) and \(rhs.0) share the same attributes")
                }
            }
            #expect(editor.comments != editor.text, "\(name): comments look like plain text")

            let terminal = theme.terminal
            #expect(terminal.background == editor.background, "\(name): terminal background differs")
            #expect(terminal.text == editor.text, "\(name): terminal text differs")
            #expect(terminal.selection == editor.selection, "\(name): terminal selection differs")
            #expect(terminal.cursor == editor.insertionPoint, "\(name): terminal cursor differs")
            #expect(terminal.green.color == editor.strings.color, "\(name): terminal green is not the string color")
            #expect(terminal.blue.color == editor.functions.color || terminal.blue.color == editor.numbers.color)
            #expect(terminal.magenta.color == editor.keywords.color || terminal.magenta.color == editor.types.color)
        }
    }

    /// Theme files written before `functions`, `operators` and `assignedVariables` existed decode with the colors
    /// those roles used to share, so their look does not change.
    @Test
    func legacyThemeFilesFallBackForNewRoles() throws {
        let bundledURL = try #require(ThemeModel.shared.bundledThemesURL)
        let data = try Data(contentsOf: bundledURL.appending(path: "Default (Dark).cetheme"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let editorJSON = try #require(json["editor"] as? [String: Any])
        #expect(editorJSON["functions"] == nil, "fixture must not define the new keys")

        let theme = try JSONDecoder().decode(Theme.self, from: data)
        #expect(theme.editor.functions == theme.editor.commands)
        #expect(theme.editor.assignedVariables == theme.editor.variables)
        #expect(theme.editor.operators == theme.editor.text)
        #expect(theme.editor["functions"] == theme.editor.functions)
        #expect(theme.editor["operators"] == theme.editor.operators)
        #expect(theme.editor["assignedVariables"] == theme.editor.assignedVariables)

        let editorTheme = theme.resolvedEditorTheme
        #expect(editorTheme.functions.color == theme.editor.commands.nsColor)
        #expect(editorTheme.operators.color == theme.editor.text.nsColor)

        // Round trip keeps the resolved roles explicit.
        let reencoded = try JSONDecoder().decode(Theme.self, from: JSONEncoder().encode(theme))
        #expect(reencoded.editor.functions == theme.editor.functions)
        #expect(reencoded.editor.operators == theme.editor.operators)
        #expect(reencoded.editor.assignedVariables == theme.editor.assignedVariables)
    }

    @Test
    func testSyncAppearanceDoesNotPublishUntilTheNextTurn() async {
        let themeModel = ThemeModel.shared
        let originalScheme = themeModel.colorScheme
        let opposite: ColorScheme = originalScheme == .dark ? .light : .dark
        defer {
            themeModel.applyAppearance(originalScheme, matchAppearance: false)
        }

        var publications = 0
        let cancellable = themeModel.objectWillChange.sink { publications += 1 }
        themeModel.syncAppearance(to: opposite, matchAppearance: false)
        #expect(themeModel.colorScheme == originalScheme)
        #expect(publications == 0)
        cancellable.cancel()

        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
        #expect(themeModel.colorScheme == opposite)
    }

    @Test
    func testApplyAppearanceSkipsUnchangedValues() {
        let themeModel = ThemeModel.shared
        let originalScheme = themeModel.colorScheme
        let originalTheme = themeModel.selectedTheme
        defer {
            themeModel.applyAppearance(originalScheme, matchAppearance: false)
            themeModel.selectedTheme = originalTheme
        }

        themeModel.applyAppearance(.light, matchAppearance: false)
        themeModel.selectedTheme = themeModel.selectedLightTheme

        var publications = 0
        let cancellable = themeModel.objectWillChange.sink { publications += 1 }
        themeModel.applyAppearance(.light, matchAppearance: true)
        #expect(publications == 0)
        #expect(themeModel.selectedTheme == themeModel.selectedLightTheme)
        cancellable.cancel()
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
