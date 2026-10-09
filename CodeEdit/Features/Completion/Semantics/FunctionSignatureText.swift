//
//  FunctionSignatureText.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// Turns the header of a function definition into one line of prompt text.
enum FunctionSignatureText {
    /// The longest signature kept, in characters.
    static let maxLength = 300

    /// The text of a function definition from its start up to (not including) its body, as one line: runs of
    /// whitespace collapsed, at most ``maxLength`` characters. `nil` when nothing is left.
    /// - Parameters:
    ///   - text: The document.
    ///   - functionStart: The offset where the function definition starts.
    ///   - bodyStart: The offset of the function's `{`, or `nil` when the body is missing.
    static func signature(in text: String, functionStart: Int, bodyStart: Int?) -> String? {
        let string = text as NSString
        guard functionStart >= 0, functionStart < string.length else { return nil }
        let end = min(bodyStart ?? string.length, string.length)
        guard end > functionStart else { return nil }
        let length = min(end - functionStart, maxLength * 2)
        let header = string.substring(with: NSRange(location: functionStart, length: length))
        let collapsed = header.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maxLength))
    }

    // MARK: - Without a syntax tree

    /// How far back from the cursor the fallback scan looks, in UTF-16 units.
    static let searchWindow = 8_000

    /// Words that put a parenthesis in front of a block without naming a function.
    private static let controlWords: Set<String> = [
        "if", "for", "while", "switch", "catch", "return", "sizeof", "decltype", "alignof", "do", "else"
    ]
    /// Words that may stand between a function's `)` and its `{`.
    private static let trailingQualifiers: Set<String> = ["const", "noexcept", "override", "final", "volatile"]

    /// What a text scan finds around an offset.
    enum Enclosure: Equatable {
        /// The offset is in the body of a function whose declaration begins with this text, up to the
        /// function's name: its return type with any specifiers, for example `static std::string *`.
        case function(returnText: String)
        /// The offset is in a lambda or in a function with a trailing return type, whose return type the
        /// text scan does not read.
        case opaque
    }

    /// The header of the function whose body contains `offset`, found by scanning the text, or `nil`.
    ///
    /// A half-typed statement such as `ret` in a function body is often parsed as part of a declaration, so
    /// the syntax tree has no `function_definition` around the cursor exactly when the user is typing. This
    /// reads the text instead: it walks back to the innermost unclosed `{` whose head looks like
    /// `name(...) [qualifiers] {` and is not a control statement or a lambda, and returns the declaration
    /// from its start. Braces inside strings and comments are not told apart, which is acceptable for a
    /// hint to a model.
    static func enclosing(in text: String, before offset: Int) -> String? {
        let units = Array(text.utf16)
        let end = max(0, min(offset, units.count))
        let lower = max(0, end - searchWindow)
        guard case let .function(start, _, brace)? = scan(units, end: end, lower: lower, stopAtOpaque: false) else {
            return nil
        }
        return normalize(String(decoding: units[start..<brace], as: UTF16.self))
    }

    /// The innermost function body around `offset`, found by scanning the text, for the `return` slot.
    ///
    /// Like ``enclosing(in:before:)``, but a lambda body or a function with a trailing return type that is
    /// reached first answers ``Enclosure/opaque`` instead of being skipped, because a `return` there does
    /// not return the type of the function around it. `nil` when no function body is found.
    static func enclosure(in text: String, before offset: Int) -> Enclosure? {
        let string = text as NSString
        let end = max(0, min(offset, string.length))
        let lower = max(0, end - searchWindow)
        let units = Array(string.substring(with: NSRange(location: lower, length: end - lower)).utf16)
        switch scan(units, end: units.count, lower: 0, stopAtOpaque: true) {
        case let .function(start, nameStart, _)?:
            let returnText = normalize(String(decoding: units[start..<nameStart], as: UTF16.self))
            return .function(returnText: returnText ?? "")
        case .opaque?:
            return .opaque
        case nil:
            return nil
        }
    }

    /// Where a text scan stopped.
    private enum ScanResult {
        /// A function body that opens at `brace`; its declaration starts at `start` and its name at `nameStart`.
        case function(start: Int, nameStart: Int, brace: Int)
        case opaque
    }

    private static func scan(_ units: [UInt16], end: Int, lower: Int, stopAtOpaque: Bool) -> ScanResult? {
        var depth = 0
        var index = end - 1
        while index >= lower {
            switch units[index] {
            case code("}"):
                depth += 1
            case code("{"):
                if depth > 0 {
                    depth -= 1
                } else if let head = headerStart(of: units, braceIndex: index, lower: lower) {
                    return .function(start: head.start, nameStart: head.nameStart, brace: index)
                } else if stopAtOpaque, opensOpaqueBody(units, braceIndex: index, lower: lower) {
                    return .opaque
                }
            default:
                break
            }
            index -= 1
        }
        return nil
    }

    /// Whether the brace at `braceIndex` opens a lambda body (`[..](..) {`, `[..] {`) or the body of a
    /// function with a trailing return type (`auto f() -> int {`).
    private static func opensOpaqueBody(_ units: [UInt16], braceIndex: Int, lower: Int) -> Bool {
        let cursor = skipQualifiers(units, from: braceIndex - 1, lower: lower)
        guard cursor >= lower else { return false }
        switch units[cursor] {
        case code("]"):
            return true
        case code(")"):
            guard let open = matchingOpenParenthesis(for: cursor, in: units, lower: lower) else { return false }
            var before = open - 1
            while before >= lower, isWhitespace(units[before]) { before -= 1 }
            return before >= lower && units[before] == code("]")
        default:
            // A trailing return type: its arrow stands within the same statement, after a `)` or `]`.
            var index = cursor
            while index > lower,
                  units[index] != code(";"), units[index] != code("{"), units[index] != code("}") {
                if units[index] == code(">"), units[index - 1] == code("-") {
                    let beforeArrow = skipQualifiers(units, from: index - 2, lower: lower)
                    return beforeArrow >= lower
                        && (units[beforeArrow] == code(")") || units[beforeArrow] == code("]"))
                }
                index -= 1
            }
            return false
        }
    }

    /// Steps back over whitespace, `&` and the qualifiers that may stand between a `)` and a `{`.
    private static func skipQualifiers(_ units: [UInt16], from start: Int, lower: Int) -> Int {
        var cursor = start
        while cursor >= lower {
            if isWhitespace(units[cursor]) || units[cursor] == code("&") {
                cursor -= 1
            } else if let last = word(endingAt: cursor, in: units, lower: lower),
                      trailingQualifiers.contains(last.text) || last.text == "mutable" {
                cursor = last.start - 1
            } else {
                break
            }
        }
        return cursor
    }

    /// Where the declaration whose body opens at `braceIndex` starts, or `nil` when that brace does not open
    /// a function body.
    private static func headerStart(
        of units: [UInt16],
        braceIndex: Int,
        lower: Int
    ) -> (start: Int, nameStart: Int)? {
        var cursor = braceIndex - 1
        // Qualifiers and reference markers between `)` and `{`.
        while cursor >= lower {
            if isWhitespace(units[cursor]) || units[cursor] == code("&") {
                cursor -= 1
            } else if let last = word(endingAt: cursor, in: units, lower: lower),
                      trailingQualifiers.contains(last.text) {
                cursor = last.start - 1
            } else {
                break
            }
        }
        guard cursor >= lower, units[cursor] == code(")"),
              let open = matchingOpenParenthesis(for: cursor, in: units, lower: lower) else {
            return nil
        }
        var nameEnd = open - 1
        while nameEnd >= lower, isWhitespace(units[nameEnd]) { nameEnd -= 1 }
        var nameStart = nameEnd + 1
        while nameStart > lower, isNameCharacter(units[nameStart - 1]) { nameStart -= 1 }
        guard nameStart <= nameEnd else { return nil }
        let qualifiedName = String(decoding: units[nameStart...nameEnd], as: UTF16.self)
        let baseName = qualifiedName.components(separatedBy: "::").last ?? qualifiedName
        guard let first = baseName.unicodeScalars.first,
              !controlWords.contains(baseName),
              first == "~" || first == "_" || CharacterSet.letters.contains(first) else {
            return nil
        }
        return (declarationStart(before: nameStart, in: units, lower: lower), nameStart)
    }

    /// The start of the declaration that has its name at `nameStart`: just after the previous `;`, `{`, `}`,
    /// access label or preprocessor line.
    private static func declarationStart(before nameStart: Int, in units: [UInt16], lower: Int) -> Int {
        var index = nameStart - 1
        while index >= lower {
            let unit = units[index]
            if unit == code(";") || unit == code("{") || unit == code("}") {
                return index + 1
            }
            if unit == code(":"),
               !(index > lower && units[index - 1] == code(":")),
               !(index + 1 < units.count && units[index + 1] == code(":")) {
                return index + 1
            }
            if unit == code("\n"), isPreprocessorLine(endingBefore: index, in: units, lower: lower) {
                return index + 1
            }
            index -= 1
        }
        return lower
    }

    private static func isPreprocessorLine(endingBefore newline: Int, in units: [UInt16], lower: Int) -> Bool {
        var start = newline
        while start > lower, units[start - 1] != code("\n") { start -= 1 }
        var cursor = start
        while cursor < newline, isWhitespace(units[cursor]) { cursor += 1 }
        return cursor < newline && units[cursor] == code("#")
    }

    private static func matchingOpenParenthesis(for close: Int, in units: [UInt16], lower: Int) -> Int? {
        var depth = 0
        var index = close
        while index >= lower {
            if units[index] == code(")") {
                depth += 1
            } else if units[index] == code("(") {
                depth -= 1
                if depth == 0 { return index }
            }
            index -= 1
        }
        return nil
    }

    private static func word(endingAt end: Int, in units: [UInt16], lower: Int) -> (text: String, start: Int)? {
        guard isIdentifierCharacter(units[end]) else { return nil }
        var start = end
        while start > lower, isIdentifierCharacter(units[start - 1]) { start -= 1 }
        return (String(decoding: units[start...end], as: UTF16.self), start)
    }

    /// The UTF-16 code unit of an ASCII character.
    private static func code(_ character: Unicode.Scalar) -> UInt16 {
        UInt16(character.value)
    }

    private static func isWhitespace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D
    }

    private static func isIdentifierCharacter(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
    }

    private static func isNameCharacter(_ unit: UInt16) -> Bool {
        isIdentifierCharacter(unit) || unit == code(":") || unit == code("~")
    }

    /// One line, whitespace collapsed, line comments dropped, at most ``maxLength`` characters.
    private static func normalize(_ header: String) -> String? {
        let withoutComments = header.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? String(line) }
            .joined(separator: " ")
        let collapsed = withoutComments.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? nil : String(collapsed.prefix(maxLength))
    }
}
