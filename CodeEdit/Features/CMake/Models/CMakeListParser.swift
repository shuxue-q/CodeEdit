//
//  CMakeListParser.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/11/26.
//

import Foundation

/// Reads literal `project()` metadata, including simple preceding `set()` variables.
/// This is deliberately not a CMake interpreter: commands in control-flow blocks are skipped.
enum CMakeListParser {
    struct Metadata {
        var name: String?
        var version: String?
        var languages: [String] = []
    }

    static func parse(_ source: String) throws -> Metadata {
        var lexer = Lexer(characters: Array(source))
        var variables: [String: String] = [:]
        var blockDepth = 0
        while let command = try lexer.next() {
            let arguments = try lexer.arguments()
            let command = command.value.lowercased()
            if ["endif", "endforeach", "endwhile", "endfunction", "endmacro", "endblock"].contains(command) {
                blockDepth = max(0, blockDepth - 1)
                continue
            }
            if ["if", "foreach", "while", "function", "macro", "block"].contains(command) {
                blockDepth += 1
                continue
            }
            guard blockDepth == 0 else {
                // A conditional assignment makes an earlier literal value uncertain.
                if command == "set", let name = arguments.first { variables[name] = nil }
                continue
            }
            let expanded = arguments.map { expand($0, variables: variables) }
            if command == "set", let name = arguments.first {
                variables[name] = arguments.count == 2 ? expanded[1] : nil
            }
            if command == "unset", let name = arguments.first { variables[name] = nil }
            if command == "project" { return metadata(expanded) }
        }
        return Metadata()
    }

    private static func expand(_ value: String, variables: [String: String]) -> String? {
        var result = value
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "${\(key)}", with: value)
        }
        return result.contains("$") ? nil : result
    }

    private static func metadata(_ arguments: [String?]) -> Metadata {
        guard let first = arguments.first else { return Metadata() }
        var result = Metadata(name: first)
        let keywords = ["VERSION", "DESCRIPTION", "HOMEPAGE_URL", "LANGUAGES", "COMPAT_VERSION", "SPDX_LICENSE"]
        if let index = arguments.firstIndex(of: "VERSION"), index + 1 < arguments.count {
            result.version = arguments[index + 1]
        }
        if let index = arguments.firstIndex(of: "LANGUAGES") {
            result.languages = arguments.dropFirst(index + 1).prefix { !keywords.contains($0 ?? "") }.compactMap { $0 }
        } else if arguments.dropFirst().contains(where: { keywords.contains($0 ?? "") }) {
            result.languages = ["C", "CXX"]
        } else {
            result.languages = arguments.count == 1 ? ["C", "CXX"] : arguments.dropFirst().compactMap { $0 }
        }
        result.languages.removeAll { $0 == "NONE" }
        return result
    }

    /// Tokenizes comments, quoted arguments and bracket arguments before looking for commands.
    private struct Lexer {
        struct Token {
            let value: String
            var delimiter = false
        }

        let characters: [Character]
        var index = 0

        mutating func arguments() throws -> [String] {
            guard let opening = try next(), opening.delimiter, opening.value == "(" else {
                throw CMakeParseError("Expected '(' after command name.")
            }
            var result: [String] = []
            var depth = 1
            while let token = try next() {
                if token.delimiter { depth += token.value == "(" ? 1 : -1 }
                if depth == 0 { return result }
                result.append(token.value)
            }
            throw CMakeParseError("Unclosed command.")
        }

        mutating func skipComments() throws {
            while index < characters.count {
                if characters[index].isWhitespace { index += 1; continue }
                if characters[index] == "#" {
                    index += 1
                    if try bracket() == nil {
                        while index < characters.count, characters[index] != "\n" { index += 1 }
                    }
                    continue
                }
                break
            }
        }

        mutating func next() throws -> Token? {
            try skipComments()
            guard index < characters.count else { return nil }
            if let value = try bracket() { return Token(value: value) }
            let first = characters[index]
            index += 1
            if first == "(" || first == ")" { return Token(value: String(first), delimiter: true) }
            let quoted = first == "\""
            var value = quoted ? "" : String(first)
            while index < characters.count {
                let character = characters[index]
                if quoted, character == "\"" { index += 1; return Token(value: value) }
                if !quoted, character.isWhitespace || ["(", ")", "#"].contains(character) {
                    break
                }
                index += 1
                if character == "\\", index < characters.count {
                    let escaped = characters[index]
                    index += 1
                    if escaped != "\n" { value.append(escaped) }
                } else {
                    value.append(character)
                }
            }
            if quoted { throw CMakeParseError("Unclosed quoted argument.") }
            return Token(value: value)
        }

        mutating func bracket() throws -> String? {
            guard index < characters.count, characters[index] == "[" else { return nil }
            var end = index + 1
            while end < characters.count, characters[end] == "=" { end += 1 }
            guard end < characters.count, characters[end] == "[" else { return nil }
            let closing = Array("]" + String(repeating: "=", count: end - index - 1) + "]")
            index = end + 1
            if index < characters.count, characters[index] == "\n" { index += 1 }
            let start = index
            while index + closing.count <= characters.count {
                if Array(characters[index..<(index + closing.count)]) == closing {
                    let value = String(characters[start..<index])
                    index += closing.count
                    return value
                }
                index += 1
            }
            throw CMakeParseError("Unclosed bracket argument or comment.")
        }
    }
}
