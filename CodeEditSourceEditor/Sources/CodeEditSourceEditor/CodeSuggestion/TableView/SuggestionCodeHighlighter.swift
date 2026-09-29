//
//  SuggestionCodeHighlighter.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit Contributors on 9/27/26.
//

import AppKit

/// Colors used while rendering completion documentation.
struct SuggestionDocPalette {
    var text: NSColor
    var keyword: NSColor
    var type: NSColor
    var string: NSColor
    var number: NSColor
    var comment: NSColor
    var function: NSColor
    var variable: NSColor

    init(theme: EditorTheme?) {
        text = theme?.text.color ?? .labelColor
        keyword = theme?.keywords.color ?? .systemPurple
        type = theme?.types.color ?? .systemTeal
        string = theme?.strings.color ?? .systemRed
        number = theme?.numbers.color ?? .systemBlue
        comment = theme?.comments.color ?? .secondaryLabelColor
        function = theme?.commands.color ?? .systemBlue
        variable = theme?.variables.color ?? .systemTeal
    }
}

/// Syntax colors for a fenced code block in the completion panel.
enum SuggestionCodeHighlighter {
    static func highlight(_ code: String, font: NSFont, palette: SuggestionDocPalette) -> NSAttributedString {
        let mono = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
        let semi = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 1
        paragraph.lineBreakMode = .byWordWrapping

        let result = NSMutableAttributedString()
        let characters = Array(code)
        var index = 0

        while index < characters.count {
            let token = nextToken(in: characters, index: &index)
            let face = token.emphasized ? semi : mono
            result.append(NSAttributedString(string: token.text, attributes: [
                .font: face,
                .foregroundColor: token.color(palette),
                .paragraphStyle: paragraph
            ]))
        }
        return result
    }

    private struct Token {
        var text: String
        var kind: Kind
        var emphasized: Bool

        enum Kind {
            case plain
            case keyword
            case type
            case string
            case number
            case comment
            case function
        }

        func color(_ palette: SuggestionDocPalette) -> NSColor {
            switch kind {
            case .plain: return palette.text
            case .keyword: return palette.keyword
            case .type: return palette.type
            case .string: return palette.string
            case .number: return palette.number
            case .comment: return palette.comment
            case .function: return palette.function
            }
        }
    }

    private static let keywords: Set<String> = [
        "class", "struct", "enum", "union", "namespace", "template", "typename",
        "public", "private", "protected", "static", "virtual", "override", "final",
        "const", "constexpr", "mutable", "inline", "extern", "typedef", "using",
        "return", "if", "else", "for", "while", "switch", "case", "break", "continue",
        "new", "delete", "try", "catch", "throw", "throws", "noexcept", "operator",
        "explicit", "friend", "this", "true", "false", "nullptr", "void", "int", "bool",
        "char", "float", "double", "long", "short", "unsigned", "signed", "auto",
        "concept", "requires", "func", "let", "var", "import", "include", "define",
        "fn", "pub", "impl", "trait", "def", "async", "await", "self", "protocol"
    ]

    private static func nextToken(in characters: [Character], index: inout Int) -> Token {
        let character = characters[index]
        if character == "/" && peek(characters, index, 1) == "/" {
            return Token(text: take(characters, from: &index) { $0 != "\n" }, kind: .comment, emphasized: false)
        }
        if character == "/" && peek(characters, index, 1) == "*" {
            return Token(text: takeBlockComment(characters, from: &index), kind: .comment, emphasized: false)
        }
        if character == "\"" || character == "'" {
            return Token(text: takeQuoted(characters, from: &index, quote: character), kind: .string, emphasized: false)
        }
        if character.isNumber {
            let text = take(characters, from: &index) { $0.isNumber || $0 == "." || $0 == "x" || $0 == "X" }
            return Token(text: text, kind: .number, emphasized: false)
        }
        if character == "#" || character.isLetter || character == "_" {
            return identifierToken(in: characters, index: &index)
        }
        index += 1
        return Token(text: String(character), kind: .plain, emphasized: false)
    }

    private static func identifierToken(in characters: [Character], index: inout Int) -> Token {
        let ident = take(characters, from: &index) { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "#" }
        let next = index < characters.count ? characters[index] : nil
        if ident.hasPrefix("#") || keywords.contains(ident) {
            return Token(text: ident, kind: .keyword, emphasized: true)
        }
        if ident.first?.isUppercase == true {
            return Token(text: ident, kind: .type, emphasized: false)
        }
        if next == "(" {
            return Token(text: ident, kind: .function, emphasized: false)
        }
        return Token(text: ident, kind: .plain, emphasized: false)
    }

    private static func peek(_ characters: [Character], _ index: Int, _ offset: Int) -> Character? {
        let next = index + offset
        guard next < characters.count else { return nil }
        return characters[next]
    }

    private static func take(
        _ characters: [Character],
        from index: inout Int,
        while predicate: (Character) -> Bool
    ) -> String {
        var text = ""
        while index < characters.count && predicate(characters[index]) {
            text.append(characters[index])
            index += 1
        }
        return text
    }

    private static func takeBlockComment(_ characters: [Character], from index: inout Int) -> String {
        var text = "/*"
        index += 2
        while index < characters.count {
            text.append(characters[index])
            index += 1
            if text.hasSuffix("*/") {
                break
            }
        }
        return text
    }

    private static func takeQuoted(
        _ characters: [Character],
        from index: inout Int,
        quote: Character
    ) -> String {
        var text = String(quote)
        index += 1
        while index < characters.count {
            let character = characters[index]
            text.append(character)
            index += 1
            if character == "\\" && index < characters.count {
                text.append(characters[index])
                index += 1
                continue
            }
            if character == quote {
                break
            }
        }
        return text
    }
}
