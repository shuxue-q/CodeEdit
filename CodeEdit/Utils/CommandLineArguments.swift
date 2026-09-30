//
//  CommandLineArguments.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/30/26.
//

import Foundation

/// Splits a single-line argument string the way a POSIX shell would, without expanding
/// anything: whitespace separates words, single quotes are literal, double quotes allow
/// backslash escapes of `"`, `\`, `$` and `` ` ``, and a backslash outside quotes escapes
/// the next character.
///
/// The words are handed to a process directly, so no shell ever interprets them.
enum CommandLineArguments {
    /// Splits `line` into arguments. An unterminated quote extends to the end of the line.
    static func split(_ line: String) -> [String] {
        var splitter = Splitter()
        var characters = line.makeIterator()
        while let character = characters.next() {
            splitter.consume(character, next: { characters.next() })
        }
        splitter.endWord()
        return splitter.arguments
    }

    private struct Splitter {
        var arguments: [String] = []
        var current = ""
        /// Whether a word has started, so `""` yields an empty argument.
        var hasWord = false
        var quote: Character?

        mutating func consume(_ character: Character, next: () -> Character?) {
            switch quote {
            case "'":
                if character == "'" { quote = nil } else { current.append(character) }
            case "\"":
                consumeInDoubleQuotes(character, next: next)
            default:
                consumeUnquoted(character, next: next)
            }
        }

        private mutating func consumeInDoubleQuotes(_ character: Character, next: () -> Character?) {
            if character == "\"" {
                quote = nil
            } else if character == "\\", let escaped = next() {
                if !"\"\\$`".contains(escaped) { current.append(character) }
                current.append(escaped)
            } else {
                current.append(character)
            }
        }

        private mutating func consumeUnquoted(_ character: Character, next: () -> Character?) {
            if character == "'" || character == "\"" {
                quote = character
                hasWord = true
            } else if character == "\\" {
                if let escaped = next() { current.append(escaped) }
                hasWord = true
            } else if character.isWhitespace {
                endWord()
            } else {
                current.append(character)
                hasWord = true
            }
        }

        mutating func endWord() {
            if hasWord { arguments.append(current) }
            current = ""
            hasWord = false
        }
    }
}
