//
//  LSPHoverDeclarationFormatter+Scanning.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/17/26.
//

import Foundation

extension LSPHoverDeclarationFormatter {
    static func skipAttributeOrReceiver(chars: [Character], index: inout Int) -> Bool {
        skipAtAttribute(chars: chars, index: &index)
            || skipMacroAttribute(chars: chars, index: &index)
            || skipGoReceiver(chars: chars, index: &index)
    }

    static func skipAtAttribute(chars: [Character], index: inout Int) -> Bool {
        guard chars[index] == "@" else { return false }
        index += 1
        while index < chars.count && (chars[index].isLetter || chars[index].isNumber || chars[index] == "_") {
            index += 1
        }
        while index < chars.count && chars[index] == " " { index += 1 }
        if index < chars.count && chars[index] == "(" {
            skipMatchingDelimiter(chars: chars, index: &index, open: "(", close: ")")
        }
        return true
    }

    static func skipMacroAttribute(chars: [Character], index: inout Int) -> Bool {
        guard index + 13 <= chars.count && String(chars[index..<index + 13]) == "__attribute__" else {
            return false
        }
        index += 13
        while index < chars.count && chars[index] == " " { index += 1 }
        if index < chars.count && chars[index] == "(" {
            skipMatchingDelimiter(chars: chars, index: &index, open: "(", close: ")")
        }
        return true
    }

    static func skipGoReceiver(chars: [Character], index: inout Int) -> Bool {
        guard index + 4 <= chars.count && String(chars[index..<index + 4]) == "func" else {
            return false
        }
        var cursor = index + 4
        while cursor < chars.count && chars[cursor] == " " { cursor += 1 }
        guard cursor < chars.count && chars[cursor] == "(" else { return false }

        var testIndex = cursor
        skipMatchingDelimiter(chars: chars, index: &testIndex, open: "(", close: ")")
        var afterCursor = testIndex
        while afterCursor < chars.count && chars[afterCursor] == " " { afterCursor += 1 }
        guard afterCursor < chars.count && (chars[afterCursor].isLetter || chars[afterCursor] == "_") else {
            return false
        }
        index = testIndex
        return true
    }

    static func skipMatchingDelimiter(
        chars: [Character],
        index: inout Int,
        open: Character,
        close: Character
    ) {
        guard index < chars.count && chars[index] == open else { return }
        var depth = 1
        var inQuote: Character?
        index += 1

        while index < chars.count && depth > 0 {
            let char = chars[index]
            let prev = index > 0 ? chars[index - 1] : nil

            if let quote = inQuote {
                if char == quote && prev != "\\" {
                    inQuote = nil
                }
                index += 1
                continue
            }

            if char == "\"" {
                inQuote = char
                index += 1
                continue
            }

            if char == open { depth += 1 }
            if char == close { depth -= 1 }
            index += 1
        }
    }

    /// Helper for tracking nesting depth inside parameter lists.
    struct DepthTracker {
        var paren = 1
        var bracket = 0
        var generic = 0
        var brace = 0
        var inQuote: Character?

        var isTopLevelParam: Bool {
            paren == 1 && bracket == 0 && generic == 0 && brace == 0
        }

        mutating func process(_ char: Character, prevChar: Character?, chars: [Character], index: Int) -> Bool {
            if let quote = inQuote {
                if char == quote && prevChar != "\\" {
                    inQuote = nil
                }
                return false
            }
            if char == "\"" {
                inQuote = char
                return false
            }
            if char == "'" {
                if isCharLiteral(chars: chars, index: index) {
                    inQuote = char
                }
                return false
            }
            updateDepths(char)
            return paren == 0
        }

        private func isCharLiteral(chars: [Character], index: Int) -> Bool {
            var lookAhead = index + 1
            while lookAhead < chars.count && chars[lookAhead] != "\n" && lookAhead - index <= 4 {
                if chars[lookAhead] == "'" && chars[lookAhead - 1] != "\\" {
                    return true
                }
                lookAhead += 1
            }
            return false
        }

        private mutating func updateDepths(_ char: Character) {
            switch char {
            case "(": paren += 1
            case ")": paren -= 1
            case "[": bracket += 1
            case "]": bracket -= 1
            case "<": generic += 1
            case ">": if generic > 0 { generic -= 1 }
            case "{": brace += 1
            case "}": brace -= 1
            default: break
            }
        }
    }

    /// Scans a parameter list starting after `(` to locate commas and closing `)`.
    static func scanParameters(chars: [Character], startIndex: Int) -> (closeIdx: Int, commas: [Int])? {
        var tracker = DepthTracker()
        var commaOffsets: [Int] = []

        for index in startIndex..<chars.count {
            let char = chars[index]
            let prev = index > 0 ? chars[index - 1] : nil
            let closed = tracker.process(char, prevChar: prev, chars: chars, index: index)
            if closed {
                return (closeIdx: index, commas: commaOffsets)
            }
            if char == "," && tracker.isTopLevelParam {
                commaOffsets.append(index)
            }
        }
        return nil
    }

    /// Splits parameters by comma offsets and trims each parameter cleanly.
    static func extractParams(chars: [Character], startIdx: Int, closeIdx: Int, commas: [Int]) -> [String] {
        var ranges: [ClosedRange<Int>] = []
        var curStart = startIdx

        for comma in commas {
            if curStart <= comma - 1 {
                ranges.append(curStart...(comma - 1))
            }
            curStart = comma + 1
        }
        if curStart <= closeIdx - 1 {
            ranges.append(curStart...(closeIdx - 1))
        }

        return ranges.compactMap { range in
            let text = String(chars[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            if text.contains("\n") {
                let lines = text.components(separatedBy: "\n")
                return lines.enumerated().map { idx, line in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    return idx == 0 ? "    " + trimmed : "        " + trimmed
                }.joined(separator: "\n")
            }
            return "    " + text
        }
    }
}
