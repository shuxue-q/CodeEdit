//
//  ThemeSymbolRoleTests.swift
//  CodeEditTests
//
//  Created by CodeEdit on 2026-10-10.
//

import AppKit
import Foundation
import Testing
@testable import CodeEdit

/// Tests for the symbol roles of the theme format (properties, parameters, globals, namespaces, macros,
/// preprocessor directives and primitive types) and the bundled theme that uses them.
@Suite
@MainActor
struct ThemeSymbolRoleTests {
    /// The bundled Qt Creator Light theme reproduces the Light (2024) symbol hierarchy: locals and parameters navy,
    /// fields maroon, globals orange, namespaces and types purple, macros and functions teal, keywords and
    /// primitive types olive, preprocessor directives and numbers dark blue.
    @Test
    func qtCreatorLightReproducesSymbolHierarchy() throws {
        let theme = try #require(ThemeModel.shared.themes.first { $0.displayName == "Qt Creator Light" })
        let editor = theme.editor
        #expect(editor.text.color == "#0A0A0A")
        #expect(editor.background.color == "#FCFCFC")
        #expect(editor.variables.color == "#092E64")
        #expect(editor.assignedVariables.color == "#092E64")
        #expect(editor.parameters.color == "#092E64")
        #expect(editor.properties.color == "#800000")
        #expect(editor.globals.color == "#CE5C00")
        #expect(editor.values.color == "#CE5C00")
        #expect(editor.types.color == "#800080")
        #expect(editor.namespaces.color == "#800080")
        #expect(editor.functions.color == "#00677C")
        #expect(editor.macros.color == "#00677C")
        #expect(editor.keywords.color == "#808000")
        #expect(editor.primitiveTypes.color == "#808000")
        #expect(editor.preprocessors.color == "#000080")
        #expect(editor.numbers.color == "#000080")
        #expect(editor.comments.color == "#008000")
        #expect(!editor.comments.italic, "Qt's Comment format is plain")
        #expect(editor.operators.color == editor.text.color)

        let resolved = theme.resolvedEditorTheme
        #expect(resolved.properties.color == NSColor(hex: "#800000"))
        #expect(resolved.globals.color == NSColor(hex: "#CE5C00"))
        #expect(resolved.macros.color == NSColor(hex: "#00677C"))
    }

    /// The bundled One Dark Pro themes give every symbol role of C and C++ code its own color on the dark background,
    /// while keeping the One Dark identity: green strings, grey italic comments, purple keywords, blue functions and
    /// yellow types.
    @Test(arguments: ["One Dark Pro Darker", "One Dark Pro"])
    func oneDarkProReproducesSymbolHierarchy(name: String) throws {
        let theme = try #require(ThemeModel.shared.themes.first { $0.displayName == name })
        let editor = theme.editor
        #expect(editor.keywords.color == "#C678DD")
        #expect(editor.strings.color == "#98C379")
        #expect(editor.types.color == "#E5C07B")
        #expect(editor.functions.color == "#61AFEF")
        #expect(editor.variables.color == "#8EA6D1")
        #expect(editor.assignedVariables.color == "#A3BAE3")
        #expect(editor.properties.color == "#E5737D")
        #expect(editor.globals.color == "#5FD3A8")
        #expect(editor.values.color == editor.globals.color)

        // Roles that must be told apart when reading a line such as
        // `p.span_ft = Dual<double>(span_m * kMToFt, 0.0);` inside a namespace with macros.
        let roles: [(String, String)] = [
            ("text", editor.text.color),
            ("locals", editor.variables.color),
            ("parameters", editor.parameters.color),
            ("fields", editor.properties.color),
            ("globals", editor.globals.color),
            ("types", editor.types.color),
            ("namespaces", editor.namespaces.color),
            ("functions", editor.functions.color),
            ("macros", editor.macros.color),
            ("keywords", editor.keywords.color),
            ("primitive types", editor.primitiveTypes.color),
            ("preprocessor", editor.preprocessors.color),
            ("numbers", editor.numbers.color),
            ("strings", editor.strings.color),
            ("comments", editor.comments.color)
        ]
        for (index, lhs) in roles.enumerated() {
            for rhs in roles[(index + 1)...] {
                #expect(lhs.1 != rhs.1, "\(name): \(lhs.0) and \(rhs.0) share the color \(lhs.1)")
            }
        }
        #expect(editor.comments.italic == (name == "One Dark Pro Darker"))

        // Fields must not read as locals, and a written local keeps its hue.
        #expect(editor.properties.color != editor.variables.color)
        #expect(editor.assignedVariables.color != editor.variables.color)

        let resolved = theme.resolvedEditorTheme
        #expect(resolved.properties.color == NSColor(hex: "#E5737D"))
        #expect(resolved.globals.color == NSColor(hex: "#5FD3A8"))
        #expect(resolved.macros.color == NSColor(hex: "#E58BB5"))
        #expect(resolved.primitiveTypes.color == NSColor(hex: "#56B6C2"))
    }

    /// Every text color of the One Dark Pro themes keeps at least 4.5:1 contrast on the editor background
    /// (comments of the original One Dark Pro excepted, which keep the theme's own grey).
    @Test(arguments: ["One Dark Pro Darker", "One Dark Pro"])
    func oneDarkProSymbolColorsAreReadable(name: String) throws {
        let theme = try #require(ThemeModel.shared.themes.first { $0.displayName == name })
        let editor = theme.editor
        let background = try #require(Self.luminance(editor.background.color))
        let roles = [
            editor.variables, editor.assignedVariables, editor.parameters, editor.properties, editor.globals,
            editor.types, editor.namespaces, editor.functions, editor.macros, editor.keywords,
            editor.primitiveTypes, editor.preprocessors, editor.numbers, editor.strings
        ]
        for role in roles {
            let foreground = try #require(Self.luminance(role.color))
            let ratio = (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
            #expect(ratio >= 4.5, "\(name): \(role.color) has contrast \(ratio)")
        }
    }

    /// Relative luminance of a `#RRGGBB` string.
    private static func luminance(_ hex: String) -> Double? {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }
        let channels = [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF].map { channel -> Double in
            let unit = Double(channel) / 255
            return unit <= 0.03928 ? unit / 12.92 : pow((unit + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }

    /// Theme files written before the symbol roles (`properties`, `parameters`, `globals`, `namespaces`, `macros`,
    /// `preprocessors`, `primitiveTypes`) existed decode to the attribute that styled the same text before.
    @Test
    func legacyThemeFilesFallBackForSymbolRoles() throws {
        let bundledURL = try #require(ThemeModel.shared.bundledThemesURL)
        let data = try Data(contentsOf: bundledURL.appending(path: "Default (Dark).cetheme"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let editorJSON = try #require(json["editor"] as? [String: Any])
        for key in ["properties", "parameters", "globals", "namespaces", "macros", "preprocessors", "primitiveTypes"] {
            #expect(editorJSON[key] == nil, "fixture must not define \(key)")
        }

        let theme = try JSONDecoder().decode(Theme.self, from: data)
        let editor = theme.editor
        #expect(editor.properties == editor.variables)
        #expect(editor.parameters == editor.variables)
        #expect(editor.globals == editor.variables)
        #expect(editor.namespaces == editor.types)
        #expect(editor.macros == editor.values)
        #expect(editor.preprocessors == editor.keywords)
        #expect(editor.primitiveTypes == editor.types)
        #expect(editor["properties"] == editor.properties)
        #expect(editor["primitiveTypes"] == editor.primitiveTypes)

        let editorTheme = theme.resolvedEditorTheme
        #expect(editorTheme.properties.color == editor.variables.nsColor)
        #expect(editorTheme.namespaces.color == editor.types.nsColor)
        #expect(editorTheme.macros.color == editor.values.nsColor)
        #expect(editorTheme.preprocessors.color == editor.keywords.nsColor)

        // Round trip keeps the resolved roles explicit.
        let reencoded = try JSONDecoder().decode(Theme.self, from: JSONEncoder().encode(theme))
        #expect(reencoded.editor.properties == editor.properties)
        #expect(reencoded.editor.macros == editor.macros)
        #expect(reencoded.editor.primitiveTypes == editor.primitiveTypes)
    }
}
