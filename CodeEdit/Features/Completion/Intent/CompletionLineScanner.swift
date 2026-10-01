//
//  CompletionLineScanner.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/30/26.
//

/// A small C-family lexer for the text on the cursor's line before the typed prefix.
///
/// It only needs to be right about the last few tokens and about whether the cursor sits inside a
/// comment or an unterminated literal, which is exactly where an incomplete line tends to confuse the
/// syntax tree.
enum CompletionLineScanner {
    /// Where the end of the scanned text sits.
    enum State: Equatable {
        /// In code.
        case code
        /// Inside an unterminated `"…"` literal.
        case string
        /// Inside an unterminated `'…'` literal.
        case character
        /// After `//`.
        case lineComment
        /// Inside an unterminated `/* …`.
        case blockComment

        /// Whether the state is inside a comment.
        var isComment: Bool { self == .lineComment || self == .blockComment }
        /// Whether the state is inside a string or character literal.
        var isLiteral: Bool { self == .string || self == .character }
    }

    /// One lexical token.
    struct Token: Equatable {
        /// The token's broad category.
        enum Kind: Equatable {
            /// An identifier or keyword.
            case word
            /// A number literal.
            case number
            /// A complete string or character literal.
            case literal
            /// An operator or punctuation, including multi-character operators such as `::` and `->`.
            case punctuation
        }

        /// The token's source text.
        let text: String
        /// The token's category.
        let kind: Kind
        /// Whether whitespace separates this token from the previous one (or from the line start).
        let hasLeadingSpace: Bool
    }

    /// The outcome of scanning a line.
    struct Result: Equatable {
        /// Where the end of the text sits.
        let state: State
        /// The complete tokens before the end of the text. Empty for comments and open literals.
        let tokens: [Token]
        /// Whether whitespace follows the last token.
        let hasTrailingSpace: Bool
    }

    /// Operators matched greedily before falling back to a single character, longest first.
    private static let operators: [String] = [
        "...", "<<=", ">>=",
        "::", "->", "==", "!=", "<=", ">=", "&&", "||", "++", "--", "<<", ">>",
        "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^="
    ]

    /// Scans `text`, which should be the cursor's line up to (not including) the typed prefix.
    static func scan(_ text: String) -> Result {
        let chars = Array(text)
        var tokens: [Token] = []
        var sawSpace = false
        var index = 0

        func append(_ end: Int, _ kind: Token.Kind) {
            let text = String(chars[index..<end])
            tokens.append(Token(text: text, kind: kind, hasLeadingSpace: sawSpace || tokens.isEmpty))
            sawSpace = false
            index = end
        }

        while index < chars.count {
            let char = chars[index]
            let next = index + 1 < chars.count ? chars[index + 1] : nil

            if char.isWhitespace {
                sawSpace = true
                index += 1
            } else if char == "/" && next == "/" {
                return Result(state: .lineComment, tokens: [], hasTrailingSpace: false)
            } else if char == "/" && next == "*" {
                guard let end = closingBlockComment(in: chars, from: index + 2) else {
                    return Result(state: .blockComment, tokens: [], hasTrailingSpace: false)
                }
                sawSpace = true
                index = end
            } else if char == "\"" || char == "'" {
                guard let end = closingQuote(char, in: chars, from: index + 1) else {
                    return Result(state: char == "\"" ? .string : .character, tokens: [], hasTrailingSpace: false)
                }
                append(end, .literal)
            } else if isWordCharacter(char) {
                append(wordEnd(in: chars, from: index), char.isNumber ? .number : .word)
            } else {
                let length = operators.first { matches($0, in: chars, at: index) }?.count ?? 1
                append(index + length, .punctuation)
            }
        }
        return Result(state: .code, tokens: tokens, hasTrailingSpace: sawSpace && !tokens.isEmpty)
    }

    /// Whether `char` can be part of an identifier or number.
    static func isWordCharacter(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || char == "_" || char == "$"
    }

    private static func wordEnd(in chars: [Character], from start: Int) -> Int {
        var end = start
        while end < chars.count, isWordCharacter(chars[end]) {
            end += 1
        }
        // Keep `1.5` / `1.` in one number token so the `.` is not read as member access.
        if chars[start].isNumber, end < chars.count, chars[end] == "." {
            end += 1
            while end < chars.count, isWordCharacter(chars[end]) {
                end += 1
            }
        }
        return end
    }

    /// The index just past the quote that closes a literal opened before `start`, honoring escapes.
    private static func closingQuote(_ quote: Character, in chars: [Character], from start: Int) -> Int? {
        var index = start
        while index < chars.count {
            if chars[index] == "\\" {
                index += 2
                continue
            }
            if chars[index] == quote {
                return index + 1
            }
            index += 1
        }
        return nil
    }

    /// The index just past the `*/` that closes a block comment opened before `start`.
    private static func closingBlockComment(in chars: [Character], from start: Int) -> Int? {
        var index = start
        while index + 1 < chars.count {
            if chars[index] == "*" && chars[index + 1] == "/" {
                return index + 2
            }
            index += 1
        }
        return nil
    }

    private static func matches(_ string: String, in chars: [Character], at index: Int) -> Bool {
        let candidate = Array(string)
        guard index + candidate.count <= chars.count else { return false }
        return Array(chars[index..<(index + candidate.count)]) == candidate
    }
}
