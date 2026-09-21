//
//  LSPCodeHighlighter+Scanners.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/16/26.
//

import AppKit
import Foundation
import SwiftUI

// MARK: - Tokenizer & Scanners

extension LSPCodeHighlighter {
    static func tokenize(code: String, symbolName: String? = nil) -> [Token] {
        let chars = Array(code)
        var tokens: [Token] = []
        var index = 0
        var previousWord: String?

        while index < chars.count {
            if let token = scanComment(chars: chars, index: &index)
                ?? scanStringOrLifetime(chars: chars, index: &index)
                ?? scanAttribute(chars: chars, index: &index)
                ?? scanNumber(chars: chars, index: &index) {
                if token.kind == .keyword {
                    previousWord = token.text
                }
                tokens.append(token)
                continue
            }
            if let token = scanWord(chars: chars, index: &index, previousWord: previousWord, symbolName: symbolName) {
                if token.kind == .keyword || token.kind == .symbolName || token.kind == .type || token.kind == .plain {
                    previousWord = token.text
                }
                tokens.append(token)
                continue
            }
            if let token = scanPunctuation(chars: chars, index: &index) {
                tokens.append(token)
                continue
            }

            tokens.append(Token(text: String(chars[index]), kind: .plain))
            index += 1
        }

        return tokens
    }

    private static func scanComment(chars: [Character], index: inout Int) -> Token? {
        if chars[index] == "/" && index + 1 < chars.count && (chars[index + 1] == "/" || chars[index + 1] == "*") {
            let isBlock = chars[index + 1] == "*"
            let start = index
            index += 2
            if isBlock {
                while index + 1 < chars.count && !(chars[index] == "*" && chars[index + 1] == "/") {
                    index += 1
                }
                index = min(chars.count, index + 2)
            } else {
                while index < chars.count && chars[index] != "\n" {
                    index += 1
                }
            }
            return Token(text: String(chars[start..<index]), kind: .comment)
        }
        if chars[index] == "#" {
            let start = index
            var lookAhead = index + 1
            while lookAhead < chars.count && chars[lookAhead].isLetter {
                lookAhead += 1
            }
            let word = String(chars[(index + 1)..<lookAhead])
            let directives: Set<String> = [
                "define", "include", "pragma", "if", "ifdef", "ifndef", "elif", "else", "endif",
                "warning", "error", "import", "line", "undef"
            ]
            if directives.contains(word) {
                index = lookAhead
                return Token(text: String(chars[start..<index]), kind: .keyword)
            }

            while index < chars.count && chars[index] != "\n" {
                index += 1
            }
            return Token(text: String(chars[start..<index]), kind: .comment)
        }
        return nil
    }

    private static func scanStringOrLifetime(chars: [Character], index: inout Int) -> Token? {
        let quote = chars[index]
        guard quote == "\"" || quote == "'" else { return nil }

        if let lifetime = scanRustLifetime(chars: chars, index: &index) {
            return lifetime
        }

        return scanQuotedString(chars: chars, index: &index, quote: quote)
    }

    private static func scanRustLifetime(chars: [Character], index: inout Int) -> Token? {
        guard chars[index] == "'", index + 1 < chars.count,
              chars[index + 1].isLetter || chars[index + 1] == "_" else {
            return nil
        }

        var lookAhead = index + 1
        var isCharLiteral = false
        while lookAhead < chars.count && chars[lookAhead] != "\n" && lookAhead - index <= 4 {
            if chars[lookAhead] == "'" {
                isCharLiteral = true
                break
            }
            lookAhead += 1
        }
        guard !isCharLiteral else { return nil }

        let start = index
        index += 1
        while index < chars.count && (chars[index].isLetter || chars[index].isNumber || chars[index] == "_") {
            index += 1
        }
        return Token(text: String(chars[start..<index]), kind: .type)
    }

    private static func scanQuotedString(chars: [Character], index: inout Int, quote: Character) -> Token {
        let start = index
        index += 1
        var escaped = false

        while index < chars.count {
            let char = chars[index]
            index += 1
            if escaped {
                escaped = false
                continue
            }
            if char == "\\" {
                escaped = true
            } else if char == quote || char == "\n" {
                break
            }
        }
        return Token(text: String(chars[start..<index]), kind: .string)
    }

    private static func scanAttribute(chars: [Character], index: inout Int) -> Token? {
        guard chars[index] == "@" && index + 1 < chars.count && chars[index + 1].isLetter else {
            return nil
        }
        let start = index
        index += 1
        while index < chars.count && (chars[index].isLetter || chars[index].isNumber || chars[index] == "_") {
            index += 1
        }
        return Token(text: String(chars[start..<index]), kind: .attribute)
    }

    private static func scanNumber(chars: [Character], index: inout Int) -> Token? {
        guard chars[index].isNumber else { return nil }
        let start = index

        if !scanHexOrBinary(chars: chars, index: &index) {
            scanDecimalOrScientific(chars: chars, index: &index)
        }

        scanNumericSuffixes(chars: chars, index: &index)
        return Token(text: String(chars[start..<index]), kind: .number)
    }

    private static func scanHexOrBinary(chars: [Character], index: inout Int) -> Bool {
        guard chars[index] == "0" && index + 1 < chars.count else { return false }
        let next = chars[index + 1]
        if next == "x" || next == "X" {
            index += 2
            while index < chars.count && (chars[index].isHexDigit || chars[index] == "_") {
                index += 1
            }
            return true
        }
        if next == "b" || next == "B" {
            index += 2
            while index < chars.count && (chars[index] == "0" || chars[index] == "1" || chars[index] == "_") {
                index += 1
            }
            return true
        }
        return false
    }

    private static func scanDecimalOrScientific(chars: [Character], index: inout Int) {
        while index < chars.count {
            let char = chars[index]
            if char.isNumber || char == "_" {
                index += 1
            } else if char == "." && index + 1 < chars.count && chars[index + 1].isNumber {
                index += 2
            } else if char == "e" || char == "E" {
                index += 1
                if index < chars.count && (chars[index] == "+" || chars[index] == "-") {
                    index += 1
                }
            } else {
                break
            }
        }
    }

    private static func scanNumericSuffixes(chars: [Character], index: inout Int) {
        let suffixes: Set<Character> = ["f", "F", "u", "U", "l", "L"]
        while index < chars.count && suffixes.contains(chars[index]) {
            index += 1
        }
    }

    private static func scanWord(
        chars: [Character],
        index: inout Int,
        previousWord: String?,
        symbolName: String?
    ) -> Token? {
        guard chars[index].isLetter || chars[index] == "_" else { return nil }
        let start = index
        while index < chars.count && (chars[index].isLetter || chars[index].isNumber || chars[index] == "_") {
            index += 1
        }
        let word = String(chars[start..<index])
        let kind = classifyWord(word, previousWord: previousWord, symbolName: symbolName, chars: chars, nextIdx: index)
        return Token(text: word, kind: kind)
    }

    private static func classifyWord(
        _ word: String,
        previousWord: String?,
        symbolName: String?,
        chars: [Character],
        nextIdx: Int
    ) -> TokenKind {
        if let symbolName {
            if word == symbolName || (symbolName.hasPrefix("~") && word == String(symbolName.dropFirst())) {
                return .symbolName
            }
        }
        if values.contains(word) {
            return .value
        }
        if primitiveTypes.contains(word) {
            return .type
        }
        if keywords.contains(word) {
            return .keyword
        }
        if isSymbolIdentifier(previousWord: previousWord) {
            return .symbolName
        }
        if isFunctionIdentifier(previousWord: previousWord) || isNextCharParen(chars: chars, nextIdx: nextIdx) {
            return .functionName
        }
        if let first = word.first, first.isUppercase && word != "Self" {
            return .type
        }
        return .plain
    }

    private static func isSymbolIdentifier(previousWord: String?) -> Bool {
        guard let prev = previousWord else { return false }
        let declarators: Set<String> = [
            "var", "let", "const", "val", "class",
            "struct", "enum", "protocol", "actor", "typealias", "type", "namespace",
            "concept", "union", "using", "mut", "func", "def", "fn", "function", "sub", "init",
            "define", "#define"
        ]
        return declarators.contains(prev)
    }

    private static func isFunctionIdentifier(previousWord: String?) -> Bool {
        guard let prev = previousWord else { return false }
        let declarators: Set<String> = ["func", "def", "fn", "function", "sub", "init"]
        return declarators.contains(prev)
    }

    private static func isNextCharParen(chars: [Character], nextIdx: Int) -> Bool {
        var cursor = nextIdx
        while cursor < chars.count && chars[cursor] == " " {
            cursor += 1
        }
        return cursor < chars.count && chars[cursor] == "("
    }

    private static func scanPunctuation(chars: [Character], index: inout Int) -> Token? {
        let multiPuncts = ["->", "=>", "::", "...", "==", "!=", "<=", ">=", "&&", "||"]
        for punct in multiPuncts where chars.count - index >= punct.count {
            let sub = String(chars[index..<index + punct.count])
            if sub == punct {
                index += punct.count
                return Token(text: sub, kind: .punctuation)
            }
        }

        let singlePuncts: Set<Character> = ["(", ")", "{", "}", "[", "]", "<", ">", ":", ";", ",", "=", "+", "-"]
        if singlePuncts.contains(chars[index]) {
            let text = String(chars[index])
            index += 1
            return Token(text: text, kind: .punctuation)
        }
        return nil
    }

    private static let keywords: Set<String> = [
        "func", "var", "let", "class", "struct", "enum", "protocol", "actor", "extension", "typealias",
        "associatedtype", "init", "deinit", "subscript", "public", "private", "fileprivate", "internal", "open",
        "static", "final", "mutating", "nonmutating", "override", "required", "convenience", "weak", "unowned",
        "lazy", "inout", "some", "any", "async", "await", "throws", "rethrows", "return", "throw", "guard",
        "if", "else", "switch", "case", "default", "for", "in", "while", "repeat", "where", "as", "is", "try",
        "catch", "self", "Self", "import", "def", "fn", "function", "pub", "const", "mut", "trait", "impl",
        "mod", "use", "constexpr", "consteval", "constinit", "template", "typename", "virtual", "inline", "auto",
        "namespace", "using", "typedef", "concept", "union", "extern", "explicit", "friend", "mutable", "volatile",
        "decltype", "noexcept", "static_assert", "package", "interface", "export", "yield", "lambda", "from",
        "global", "nonlocal", "pass", "del", "with", "select", "chan", "defer", "fallthrough", "continue", "break"
    ]

    private static let primitiveTypes: Set<String> = [
        "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Float", "Double",
        "Bool", "String", "Character", "Void", "Any", "AnyObject", "bool", "int", "char", "float", "double", "void",
        "short", "long", "signed", "unsigned", "size_t", "int32_t", "uint32_t", "int64_t", "uint64_t",
        "str", "list", "dict", "set", "tuple", "bytes",
        "u8", "u16", "u32", "u64", "u128", "usize", "i8", "i16", "i32", "i64", "i128", "isize", "f32", "f64",
        "int8", "int16", "int32", "int64", "uint8", "uint16", "uint32", "uint64", "float32", "float64", "byte",
        "rune", "error", "number", "boolean", "string", "symbol", "bigint", "unknown", "never"
    ]

    private static let values: Set<String> = [
        "true", "false", "nil", "null", "nullptr", "None", "undefined", "TRUE", "FALSE", "YES", "NO"
    ]
}
