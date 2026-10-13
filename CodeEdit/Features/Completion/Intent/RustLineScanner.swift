//
//  RustLineScanner.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/13/26.
//

/// Reads the cursor's line in a Rust file up to the cursor and says whether the cursor is in code, a
/// comment, a string, or a character literal.
///
/// Rust literals do not fit the C-family scanner: raw strings (`r#"…"#`) have no escapes and end only at
/// a quote followed by the same number of `#`, string prefixes (`b"…"`, `br"…"`, `c"…"`) look like
/// identifiers, block comments nest, and `'` opens either a character literal (`'a'`, `b'\n'`) or a
/// lifetime or loop label (`'a`, `'static`, `'outer`). This scanner runs first and hands the shared
/// tokenizer plain code: every complete string and character literal reads `""`, every closed comment a
/// space, and lifetimes stay as `'name`, which the ``CompletionLineScanner/Dialect/rust`` dialect reads
/// as one word.
///
/// A string or comment that started on an earlier line is invisible here; ``RustTokenRules`` asks the
/// syntax tree about those.
enum RustLineScanner {
    /// Where the end of the scanned text sits.
    enum State: Equatable {
        /// In code.
        case code
        /// After `//`, `///`, or `//!`.
        case lineComment
        /// Inside an unterminated `/* …`.
        case blockComment
        /// Inside an unterminated string literal of any kind.
        case string
        /// Inside an unterminated character or byte literal (`'a`, `b'\`).
        case character
    }

    /// The outcome of scanning a line.
    struct Result: Equatable {
        /// Where the end of the text sits.
        let state: State
        /// The code before the end of the text, or before the open literal or comment. Complete literals
        /// read `""`; closed comments read as a space.
        let code: String
    }

    /// Scans `text`, the cursor's line up to the cursor.
    static func scan(_ text: String) -> Result {
        let chars = Array(text)
        var code: [Character] = []
        var index = 0

        while index < chars.count {
            let char = chars[index]
            let next = index + 1 < chars.count ? chars[index + 1] : nil

            if char == "/" && next == "/" {
                return Result(state: .lineComment, code: String(code))
            }
            if char == "/" && next == "*" {
                guard let end = closingBlockComment(in: chars, from: index + 2) else {
                    return Result(state: .blockComment, code: String(code))
                }
                code.append(" ")
                index = end
                continue
            }
            if let open = openingString(in: chars, at: index) {
                guard let end = closingString(open, in: chars) else {
                    return Result(state: .string, code: String(code))
                }
                code += ["\"", "\""]
                index = end
                continue
            }
            if char == "'" || char == "b" && next == "'" && !followsWord(chars, index) {
                let quote = char == "'" ? index : index + 1
                switch quoteMeaning(in: chars, quoteAt: quote, isByte: char == "b") {
                case .character(let end):
                    code += ["\"", "\""]
                    index = end
                case .openCharacter:
                    return Result(state: .character, code: String(code))
                case .lifetime(let end):
                    code += chars[quote..<end]
                    index = end
                }
                continue
            }
            code.append(char)
            index += 1
        }
        return Result(state: .code, code: String(code))
    }

    // MARK: - Strings

    /// A string literal's opening: where its text starts and how many `#` close a raw string.
    private struct OpenString {
        let textStart: Int
        let isRaw: Bool
        let hashes: Int
    }

    /// The string literal that opens at `index`: `"`, or a prefix (`r`, `b`, `br`, `c`, `cr`) followed by
    /// `#`s (raw strings only) and `"`. A prefix that ends an identifier (`bar"`) does not open a string.
    private static func openingString(in chars: [Character], at index: Int) -> OpenString? {
        if chars[index] == "\"" {
            return OpenString(textStart: index + 1, isRaw: false, hashes: 0)
        }
        guard !followsWord(chars, index) else { return nil }
        var cursor = index
        if chars[cursor] == "b" || chars[cursor] == "c" {
            cursor += 1
        }
        var isRaw = false
        if cursor < chars.count && chars[cursor] == "r" {
            isRaw = true
            cursor += 1
        }
        guard cursor > index else { return nil }
        var hashes = 0
        while isRaw, cursor < chars.count, chars[cursor] == "#" {
            hashes += 1
            cursor += 1
        }
        guard cursor < chars.count, chars[cursor] == "\"" else { return nil }
        return OpenString(textStart: cursor + 1, isRaw: isRaw, hashes: hashes)
    }

    /// The index just past the end of `open`, or `nil` when it does not close on the line.
    private static func closingString(_ open: OpenString, in chars: [Character]) -> Int? {
        var index = open.textStart
        while index < chars.count {
            let char = chars[index]
            if !open.isRaw && char == "\\" {
                index += 2
                continue
            }
            if char == "\"" {
                let hashEnd = index + 1 + open.hashes
                if hashEnd <= chars.count && chars[(index + 1)..<hashEnd].allSatisfy({ $0 == "#" }) {
                    return hashEnd
                }
            }
            index += 1
        }
        return nil
    }

    // MARK: - Characters and lifetimes

    /// What a `'` starts.
    private enum QuoteMeaning {
        /// A complete character literal ending just before the index.
        case character(end: Int)
        /// A character literal that is still being typed.
        case openCharacter
        /// A lifetime or label: `'` and the name, ending just before the index.
        case lifetime(end: Int)
    }

    /// Decides what the `'` at `quote` starts. `'x'` and `'\n'` are characters; `'a` followed by anything
    /// but `'` is a lifetime. At the end of the line it depends on what precedes the quote: after `&`,
    /// `<`, `+`, `:`, or a keyword such as `impl`, a name is a lifetime (`&'a`, `T: 'a`); elsewhere a single
    /// character is a character literal being typed, and a longer name a label or lifetime.
    private static func quoteMeaning(in chars: [Character], quoteAt quote: Int, isByte: Bool) -> QuoteMeaning {
        let first = quote + 1
        guard first < chars.count else {
            return !isByte && lifetimeContext(chars, before: quote) ? .lifetime(end: first) : .openCharacter
        }
        if chars[first] == "\\" {
            var index = first + 2
            while index < chars.count {
                if chars[index] == "'" { return .character(end: index + 1) }
                index += 1
            }
            return .openCharacter
        }
        if first + 1 < chars.count && chars[first + 1] == "'" {
            return .character(end: first + 2)
        }
        guard !isByte, isIdentifierStart(chars[first]) else {
            return first + 1 < chars.count ? .character(end: first + 1) : .openCharacter
        }
        var end = first
        while end < chars.count, CompletionLineScanner.isWordCharacter(chars[end]) {
            end += 1
        }
        if end < chars.count || end - first > 1 || lifetimeContext(chars, before: quote) {
            return .lifetime(end: end)
        }
        return .openCharacter
    }

    /// Whether the code before `index` expects a lifetime: `&`, `<`, `+`, `:` (a bound or a label), or the
    /// keywords `impl`, `dyn`, `for`, `where`, `break`, `continue`.
    private static func lifetimeContext(_ chars: [Character], before index: Int) -> Bool {
        var cursor = index - 1
        while cursor >= 0, chars[cursor] == " " || chars[cursor] == "\t" {
            cursor -= 1
        }
        guard cursor >= 0 else { return false }
        if ["&", "<", "+", ":", ","].contains(chars[cursor]) {
            return chars[cursor] != "," || hasOpenAngle(chars, before: cursor)
        }
        var start = cursor
        while start > 0, CompletionLineScanner.isWordCharacter(chars[start - 1]) {
            start -= 1
        }
        let word = String(chars[start...cursor])
        return ["impl", "dyn", "for", "where", "break", "continue"].contains(word)
    }

    /// Whether an unclosed `<` precedes `index`: a `,` there separates generic arguments (`Foo<'a, 'b`).
    private static func hasOpenAngle(_ chars: [Character], before index: Int) -> Bool {
        var depth = 0
        for char in chars[..<index] {
            if char == "<" { depth += 1 }
            if char == ">" && depth > 0 { depth -= 1 }
        }
        return depth > 0
    }

    // MARK: - Helpers

    private static func isIdentifierStart(_ char: Character) -> Bool {
        char.isLetter || char == "_"
    }

    /// Whether the character before `index` continues an identifier, so a letter at `index` is not a
    /// literal prefix.
    private static func followsWord(_ chars: [Character], _ index: Int) -> Bool {
        index > 0 && CompletionLineScanner.isWordCharacter(chars[index - 1])
    }

    /// The index just past the `*/` that closes a block comment opened before `start`. Rust block
    /// comments nest.
    private static func closingBlockComment(in chars: [Character], from start: Int) -> Int? {
        var depth = 1
        var index = start
        while index + 1 < chars.count {
            if chars[index] == "*" && chars[index + 1] == "/" {
                depth -= 1
                index += 2
                if depth == 0 { return index }
            } else if chars[index] == "/" && chars[index + 1] == "*" {
                depth += 1
                index += 2
            } else {
                index += 1
            }
        }
        return nil
    }
}
