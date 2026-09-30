//
//  EditorTheme.swift
//  CodeEditSourceEditor
//
//  Created by Lukas Pistrol on 29.05.22.
//

import SwiftUI

/// A collection of attributes used for syntax highlighting and other colors for the editor.
///
/// Attributes of a theme that do not apply to text (background, line highlight) are a single `NSColor` for simplicity.
/// All other attributes use the ``EditorTheme/Attribute`` type to store
public struct EditorTheme: Equatable {
    /// Represents attributes that can be applied to style text.
    public struct Attribute: Equatable, Hashable, Sendable {
        public let color: NSColor
        public let bold: Bool
        public let italic: Bool

        public init(color: NSColor, bold: Bool = false, italic: Bool = false) {
            self.color = color
            self.bold = bold
            self.italic = italic
        }
    }

    public var text: Attribute
    public var insertionPoint: NSColor
    public var invisibles: Attribute
    public var background: NSColor
    public var lineHighlight: NSColor
    public var selection: NSColor
    public var keywords: Attribute
    public var commands: Attribute
    public var types: Attribute
    public var attributes: Attribute
    public var variables: Attribute
    public var values: Attribute
    public var numbers: Attribute
    public var strings: Attribute
    public var characters: Attribute
    public var comments: Attribute

    /// Explicit rainbow bracket colors, cycled by nesting depth (like VS Code's
    /// `editorBracketHighlight.foreground1…6`). When `nil` or empty, a palette suited to the theme's
    /// background is used. See ``resolvedBracketColors``.
    public var bracketColors: [NSColor]?

    public init(
        text: Attribute,
        insertionPoint: NSColor,
        invisibles: Attribute,
        background: NSColor,
        lineHighlight: NSColor,
        selection: NSColor,
        keywords: Attribute,
        commands: Attribute,
        types: Attribute,
        attributes: Attribute,
        variables: Attribute,
        values: Attribute,
        numbers: Attribute,
        strings: Attribute,
        characters: Attribute,
        comments: Attribute
    ) {
        self.text = text
        self.insertionPoint = insertionPoint
        self.invisibles = invisibles
        self.background = background
        self.lineHighlight = lineHighlight
        self.selection = selection
        self.keywords = keywords
        self.commands = commands
        self.types = types
        self.attributes = attributes
        self.variables = variables
        self.values = values
        self.numbers = numbers
        self.strings = strings
        self.characters = characters
        self.comments = comments
    }

    /// Fallback rainbow bracket palette for dark backgrounds.
    static let darkBracketColors: [NSColor] = [
        NSColor(srgbRed: 1.0, green: 0.843, blue: 0.0, alpha: 1),      // #FFD700
        NSColor(srgbRed: 0.855, green: 0.439, blue: 0.839, alpha: 1),  // #DA70D6
        NSColor(srgbRed: 0.090, green: 0.624, blue: 1.0, alpha: 1)     // #179FFF
    ]

    /// Fallback rainbow bracket palette for light backgrounds.
    static let lightBracketColors: [NSColor] = [
        NSColor(srgbRed: 0.710, green: 0.537, blue: 0.0, alpha: 1),    // #B58900
        NSColor(srgbRed: 0.545, green: 0.0, blue: 0.545, alpha: 1),    // #8B008B
        NSColor(srgbRed: 0.0, green: 0.478, blue: 0.8, alpha: 1)       // #007ACC
    ]

    /// The rainbow palette in effect: ``bracketColors`` when provided, otherwise a light or dark fallback chosen from
    /// the background's brightness.
    ///
    /// The palette always cycles evenly over ``CaptureName/bracketLevelCount`` levels, so its length is
    /// normalized to a divisor of that count: lengths 1, 2, 3 and 6 are used as given, other lengths are truncated
    /// to the largest usable prefix.
    public var resolvedBracketColors: [NSColor] {
        var palette = bracketColors ?? []
        if palette.isEmpty {
            let isLight = (background.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 0) > 0.5
            palette = isLight ? Self.lightBracketColors : Self.darkBracketColors
        }
        let usable = [6, 3, 2, 1].first(where: { $0 <= palette.count }) ?? 1
        return Array(palette.prefix(usable))
    }

    /// Maps a capture type to the theme attribute for that capture.
    private static let captureAttributeKeyPaths: [CaptureName: KeyPath<EditorTheme, Attribute>] = [
        .include: \.keywords,
        .constructor: \.keywords,
        .keyword: \.keywords,
        .boolean: \.keywords,
        .variableBuiltin: \.keywords,
        .keywordReturn: \.keywords,
        .keywordFunction: \.keywords,
        .repeat: \.keywords,
        .conditional: \.keywords,
        .tag: \.keywords,
        .label: \.keywords,
        .comment: \.comments,
        .variable: \.variables,
        .property: \.variables,
        .function: \.variables,
        .method: \.variables,
        .parameter: \.variables,
        .number: \.numbers,
        .float: \.numbers,
        .string: \.strings,
        .type: \.types,
        .typeAlternate: \.attributes,
        .constant: \.values,
        .operator: \.text
    ]

    /// Maps a capture type to the attributes for that capture determined by the theme.
    /// - Parameter capture: The capture to map to.
    /// - Returns: Theme attributes for the capture.
    private func mapCapture(_ capture: CaptureName?) -> Attribute {
        guard let capture, let keyPath = Self.captureAttributeKeyPaths[capture] else {
            return text
        }
        return self[keyPath: keyPath]
    }

    /// Get the color from ``theme`` for the specified capture name.
    /// - Parameter capture: The capture name
    /// - Returns: A `NSColor`
    func colorFor(_ capture: CaptureName?) -> NSColor {
        if let level = capture?.bracketLevelIndex {
            let palette = resolvedBracketColors
            return palette[level % palette.count]
        }
        return mapCapture(capture).color
    }

    /// Returns the correct font with attributes (bold and italics) for a given capture name.
    /// - Parameters:
    ///   - capture: The capture name.
    ///   - font: The font to add attributes to.
    /// - Returns: A new font that has the correct attributes for the capture.
    func fontFor(for capture: CaptureName?, from font: NSFont) -> NSFont {
        let attributes = mapCapture(capture)
        guard attributes.bold || attributes.italic else {
            return font
        }

        var font = font

        if attributes.bold {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }

        if attributes.italic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }

        return font
    }
}
