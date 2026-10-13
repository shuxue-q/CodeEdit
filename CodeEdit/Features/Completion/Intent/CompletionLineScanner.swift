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
///
/// The ``Dialect/dart`` dialect adds Dart's operators (`?.`, `..`, `?..`, `=>`, `??`, `??=`, `...`,
/// `...?`) and reads `'…'` as a string. The ``Dialect/rust`` dialect adds `::<`, `=>`, `..`, `..=` and
/// reads `'a` as one word (a lifetime). The C-family dialect is the default and is unaffected by them.
enum CompletionLineScanner {
    /// The operator set and quoting rules to scan with.
    enum Dialect: Equatable {
        /// C, C++, Objective-C, and the language-neutral fallback.
        case cFamily
        /// Dart: the shared operators plus the null-aware, cascade, arrow, spread, and `~/` operators.
        case dart
        /// Rust, after ``RustLineScanner`` replaced its literals: the turbofish, fat arrow, and range
        /// operators; `'name` is a lifetime word. A `.` after a number stays separate unless a digit
        /// follows it, so `0..n` is a range and `1.max(2)` a method call.
        case rust
    }

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

    /// Dart's operators, longest first. `::` and `->` are not Dart, so they are left out.
    private static let dartOperators: [String] = [
        "...?", ">>>=",
        "...", "?..", "??=", "~/=", "<<=", ">>=", ">>>",
        "?.", "..", "=>", "??", "~/", "==", "!=", "<=", ">=", "&&", "||", "++", "--", "<<", ">>",
        "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^="
    ]

    /// Rust's operators, longest first. `?` and `#` are single characters.
    private static let rustOperators: [String] = [
        "..=", "::<", "<<=", ">>=", "...",
        "::", "->", "=>", "..", "==", "!=", "<=", ">=", "&&", "||", "<<", ">>",
        "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^="
    ]

    /// Scans `text`, which should be the cursor's line up to (not including) the typed prefix.
    static func scan(_ text: String, dialect: Dialect = .cFamily) -> Result {
        let operators = operatorTable(for: dialect)
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
                guard let quoted = quotedToken(at: index, in: chars, dialect: dialect) else {
                    let isString = char == "\"" || dialect == .dart
                    return Result(state: isString ? .string : .character, tokens: [], hasTrailingSpace: false)
                }
                append(quoted.end, quoted.kind)
            } else if isWordCharacter(char) {
                append(wordEnd(in: chars, from: index, dialect: dialect), char.isNumber ? .number : .word)
            } else {
                let length = operators.first { matches($0, in: chars, at: index) }?.count ?? 1
                append(index + length, .punctuation)
            }
        }
        return Result(state: .code, tokens: tokens, hasTrailingSpace: sawSpace && !tokens.isEmpty)
    }

    private static func operatorTable(for dialect: Dialect) -> [String] {
        switch dialect {
        case .cFamily: return operators
        case .dart: return dartOperators
        case .rust: return rustOperators
        }
    }

    /// The token a quote at `index` starts, or `nil` when the literal is not closed on the line. In Rust a
    /// `'` is a lifetime or label (`RustLineScanner` already replaced character literals): one word with
    /// its name, or punctuation on its own.
    private static func quotedToken(
        at index: Int,
        in chars: [Character],
        dialect: Dialect
    ) -> (end: Int, kind: Token.Kind)? {
        guard dialect == .rust && chars[index] == "'" else {
            return closingQuote(chars[index], in: chars, from: index + 1).map { ($0, .literal) }
        }
        guard index + 1 < chars.count, isWordCharacter(chars[index + 1]) else {
            return (index + 1, .punctuation)
        }
        return (wordEnd(in: chars, from: index + 1, dialect: dialect), .word)
    }

    /// Whether `char` can be part of an identifier or number.
    static func isWordCharacter(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || char == "_" || char == "$"
    }

    private static func wordEnd(in chars: [Character], from start: Int, dialect: Dialect) -> Int {
        var end = start
        while end < chars.count, isWordCharacter(chars[end]) {
            end += 1
        }
        // Keep `1.5` / `1.` in one number token so the `.` is not read as member access. In Rust only when
        // a digit or nothing follows the `.`: `0..n` is a range, `1.max(2)` a call, `t.0.1` a tuple field.
        if dialect == .rust {
            let isFraction = end < chars.count && chars[end] == "."
                && (end + 1 == chars.count || chars[end + 1].isNumber)
                && !(start > 0 && chars[start - 1] == ".")
            guard chars[start].isNumber, isFraction else { return end }
            end += 1
            while end < chars.count, isWordCharacter(chars[end]) {
                end += 1
            }
            return end
        }
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
