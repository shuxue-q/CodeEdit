//
//  TOMLParser.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

// MARK: - Parser

/// The scanner behind ``TOMLDocument/parse(_:)``.
struct TOMLParser {
    let chars: [Character]
    var index = 0
    var line = 1

    init(text: String) {
        chars = Array(text)
    }

    mutating func parseDocument() -> TOMLDocument {
        var document = TOMLDocument()
        var currentPath: [String] = []
        while true {
            skipWhitespaceCommentsAndNewlines()
            guard index < chars.count else { break }
            let startLine = line
            do {
                if chars[index] == "[" {
                    currentPath = try parseHeader(into: &document.root)
                } else {
                    let (keys, value) = try parseKeyValue()
                    try insert(value, keys: keys, under: currentPath, in: &document.root)
                }
                try expectLineEnd()
            } catch var error as TOMLParseError {
                error.line = startLine
                document.errors.append(error)
                skipToNextLine()
            } catch {
                skipToNextLine()
            }
        }
        return document
    }

    // MARK: Structure

    /// Parses `[a.b]` or `[[a.b]]` and returns the path new keys go under.
    private mutating func parseHeader(into root: inout TOMLTable) throws -> [String] {
        index += 1
        let isArray = peek() == "["
        if isArray { index += 1 }
        skipInlineWhitespace()
        let path = try parseKey()
        skipInlineWhitespace()
        try expect("]")
        if isArray { try expect("]") }
        if isArray {
            let parent = path.dropLast()
            let last = path[path.count - 1]
            try root.withTable(at: parent) { table in
                var array = table[last]?.array ?? []
                if table[last] != nil && table[last]?.array == nil {
                    throw TOMLParseError(message: "'\(last)' is not an array of tables")
                }
                array.append(.table(TOMLTable()))
                table[last] = .array(array)
            }
        } else {
            try root.withTable(at: path[...]) { _ in }
        }
        return path
    }

    private func insert(
        _ value: TOMLValue,
        keys: [String],
        under path: [String],
        in root: inout TOMLTable
    ) throws {
        let last = keys[keys.count - 1]
        try root.withTable(at: (path + keys.dropLast())[...]) { table in
            if table[last] != nil {
                throw TOMLParseError(message: "'\(last)' is defined twice")
            }
            table[last] = value
        }
    }

    private mutating func parseKeyValue() throws -> ([String], TOMLValue) {
        let keys = try parseKey()
        skipInlineWhitespace()
        try expect("=")
        skipInlineWhitespace()
        return (keys, try parseValue())
    }

    /// Parses a dotted key of bare and quoted segments.
    private mutating func parseKey() throws -> [String] {
        var keys: [String] = []
        while true {
            skipInlineWhitespace()
            guard let char = peek() else { throw TOMLParseError(message: "Expected a key") }
            if char == "\"" {
                keys.append(try parseBasicString())
            } else if char == "'" {
                keys.append(try parseLiteralString())
            } else {
                let start = index
                while let next = peek(), next.isLetter || next.isNumber || next == "_" || next == "-" {
                    index += 1
                }
                guard index > start else { throw TOMLParseError(message: "Expected a key") }
                keys.append(String(chars[start..<index]))
            }
            skipInlineWhitespace()
            guard peek() == "." else { return keys }
            index += 1
        }
    }

    // MARK: Values

    private mutating func parseValue() throws -> TOMLValue {
        guard let char = peek() else { throw TOMLParseError(message: "Expected a value") }
        switch char {
        case "\"":
            return .string(hasPrefix("\"\"\"") ? try parseMultilineBasicString() : try parseBasicString())
        case "'":
            return .string(hasPrefix("'''") ? try parseMultilineLiteralString() : try parseLiteralString())
        case "[":
            return try parseArray()
        case "{":
            return try parseInlineTable()
        default:
            return try parseScalar()
        }
    }

    private mutating func parseArray() throws -> TOMLValue {
        index += 1
        var values: [TOMLValue] = []
        while true {
            skipWhitespaceCommentsAndNewlines()
            guard let char = peek() else { throw TOMLParseError(message: "Unterminated array") }
            if char == "]" {
                index += 1
                return .array(values)
            }
            values.append(try parseValue())
            skipWhitespaceCommentsAndNewlines()
            if peek() == "," {
                index += 1
            } else if peek() != "]" {
                throw TOMLParseError(message: "Expected ',' or ']' in array")
            }
        }
    }

    private mutating func parseInlineTable() throws -> TOMLValue {
        index += 1
        var table = TOMLTable()
        skipInlineWhitespace()
        if peek() == "}" {
            index += 1
            return .table(table)
        }
        while true {
            skipInlineWhitespace()
            let (keys, value) = try parseKeyValue()
            let last = keys[keys.count - 1]
            try table.withTable(at: keys.dropLast()) { inner in
                if inner[last] != nil { throw TOMLParseError(message: "'\(last)' is defined twice") }
                inner[last] = value
            }
            skipInlineWhitespace()
            guard let char = peek() else { throw TOMLParseError(message: "Unterminated inline table") }
            index += 1
            if char == "}" { return .table(table) }
            guard char == "," else { throw TOMLParseError(message: "Expected ',' or '}' in inline table") }
        }
    }

    /// Parses a Boolean, number or date: everything up to the next delimiter.
    private mutating func parseScalar() throws -> TOMLValue {
        let start = index
        while let char = peek(), !char.isNewline, !",]}#".contains(char) {
            // A space separates a date from its time (`1979-05-27 07:32:00`); allow that one.
            if char == " " || char == "\t" {
                let text = String(chars[start..<index])
                guard isDate(text), let next = peek(at: index + 1), next.isNumber else { break }
            }
            index += 1
        }
        let token = String(chars[start..<index]).trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { throw TOMLParseError(message: "Expected a value") }
        if token == "true" { return .boolean(true) }
        if token == "false" { return .boolean(false) }
        if let integer = Self.integer(token) { return .integer(integer) }
        if let float = Self.float(token) { return .float(float) }
        if isDate(token) || token.contains(":") { return .dateTime(token) }
        throw TOMLParseError(message: "Invalid value '\(token)'")
    }

    private func isDate(_ text: String) -> Bool {
        let scalars = Array(text)
        return scalars.count >= 10 && scalars[4] == "-" && scalars[7] == "-"
            && scalars[0..<4].allSatisfy(\.isNumber)
    }

    private static func integer(_ token: String) -> Int? {
        let cleaned = token.replacingOccurrences(of: "_", with: "")
        for (prefix, radix) in [("0x", 16), ("0o", 8), ("0b", 2)] where cleaned.hasPrefix(prefix) {
            return Int(cleaned.dropFirst(2), radix: radix)
        }
        guard cleaned.allSatisfy({ $0.isNumber || $0 == "+" || $0 == "-" }) else { return nil }
        return Int(cleaned)
    }

    private static func float(_ token: String) -> Double? {
        let cleaned = token.replacingOccurrences(of: "_", with: "")
        switch cleaned {
        case "inf", "+inf": return .infinity
        case "-inf": return -.infinity
        case "nan", "+nan", "-nan": return .nan
        default: return Double(cleaned)
        }
    }

    // MARK: Scanning helpers

    func peek() -> Character? {
        index < chars.count ? chars[index] : nil
    }

    private func peek(at position: Int) -> Character? {
        position < chars.count ? chars[position] : nil
    }

    func hasPrefix(_ prefix: String) -> Bool {
        var position = index
        for char in prefix {
            guard position < chars.count, chars[position] == char else { return false }
            position += 1
        }
        return true
    }

    private mutating func expect(_ char: Character) throws {
        guard peek() == char else { throw TOMLParseError(message: "Expected '\(char)'") }
        index += 1
    }

    private mutating func skipInlineWhitespace() {
        while let char = peek(), char == " " || char == "\t" { index += 1 }
    }

    private mutating func skipComment() {
        guard peek() == "#" else { return }
        while let char = peek(), !char.isNewline { index += 1 }
    }

    private mutating func skipWhitespaceCommentsAndNewlines() {
        while let char = peek() {
            if char == " " || char == "\t" {
                index += 1
            } else if char.isNewline {
                index += 1
                line += 1
            } else if char == "#" {
                skipComment()
            } else {
                return
            }
        }
    }

    /// After a value or header only whitespace and a comment may follow on the line.
    private mutating func expectLineEnd() throws {
        skipInlineWhitespace()
        skipComment()
        guard let char = peek() else { return }
        guard char.isNewline else { throw TOMLParseError(message: "Unexpected text after value") }
    }

    private mutating func skipToNextLine() {
        while let char = peek(), !char.isNewline { index += 1 }
    }
}
