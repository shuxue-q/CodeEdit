//
//  TOMLParser+Strings.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

// MARK: - Strings

extension TOMLParser {
    mutating func parseBasicString() throws -> String {
        index += 1
        var result = ""
        // Stop before a newline so the line counter and error recovery see it.
        while let char = peek(), !char.isNewline {
            index += 1
            if char == "\"" { return result }
            if char == "\\" {
                result.append(try parseEscape())
            } else {
                result.append(char)
            }
        }
        throw TOMLParseError(message: "Unterminated string")
    }

    mutating func parseLiteralString() throws -> String {
        index += 1
        let start = index
        while let char = peek() {
            if char == "'" {
                let value = String(chars[start..<index])
                index += 1
                return value
            }
            if char.isNewline { break }
            index += 1
        }
        throw TOMLParseError(message: "Unterminated string")
    }

    mutating func parseMultilineBasicString() throws -> String {
        index += 3
        skipLeadingNewline()
        var result = ""
        while index < chars.count {
            if hasPrefix("\"\"\"") {
                index += 3
                // Up to two quotes may directly precede the closing delimiter.
                for _ in 0..<2 where peek() == "\"" {
                    result.append("\"")
                    index += 1
                }
                return result
            }
            let char = chars[index]
            index += 1
            if char.isNewline { line += 1 }
            if char == "\\" {
                if let next = peek(), next == " " || next == "\t" || next.isNewline {
                    // A line-ending backslash trims the newline and following whitespace.
                    while let skip = peek(), skip == " " || skip == "\t" || skip.isNewline {
                        if skip.isNewline { line += 1 }
                        index += 1
                    }
                } else {
                    result.append(try parseEscape())
                }
            } else {
                result.append(char)
            }
        }
        throw TOMLParseError(message: "Unterminated multi-line string")
    }

    mutating func parseMultilineLiteralString() throws -> String {
        index += 3
        skipLeadingNewline()
        var result = ""
        while index < chars.count {
            if hasPrefix("'''") {
                index += 3
                for _ in 0..<2 where peek() == "'" {
                    result.append("'")
                    index += 1
                }
                return result
            }
            if chars[index].isNewline { line += 1 }
            result.append(chars[index])
            index += 1
        }
        throw TOMLParseError(message: "Unterminated multi-line string")
    }

    /// The characters a backslash escape stands for, other than Unicode escapes.
    private static let simpleEscapes: [Character: Character] = [
        "b": "\u{08}", "t": "\t", "n": "\n", "f": "\u{0C}", "r": "\r", "e": "\u{1B}", "\"": "\"", "\\": "\\"
    ]

    private mutating func parseEscape() throws -> Character {
        guard let char = peek() else { throw TOMLParseError(message: "Invalid escape") }
        index += 1
        if let escaped = Self.simpleEscapes[char] { return escaped }
        guard char == "u" || char == "U" else { throw TOMLParseError(message: "Invalid escape '\\\(char)'") }
        let length = char == "u" ? 4 : 8
        guard index + length <= chars.count,
              let code = UInt32(String(chars[index..<index + length]), radix: 16),
              let scalar = Unicode.Scalar(code) else {
            throw TOMLParseError(message: "Invalid Unicode escape")
        }
        index += length
        return Character(scalar)
    }

    private mutating func skipLeadingNewline() {
        if peek() == "\r\n" || peek() == "\n" {
            index += 1
            line += 1
        }
    }

}
