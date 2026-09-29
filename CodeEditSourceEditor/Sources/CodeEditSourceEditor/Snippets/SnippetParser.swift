//
//  SnippetParser.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit Contributors on 9/29/26.
//

import Foundation

/// A tab stop in a parsed snippet.
public struct SnippetTabStop: Equatable, Sendable {
    /// The snippet's tab-stop number. `0` is the final cursor position.
    public let index: Int
    /// The range of the placeholder text, in UTF-16 offsets into ``ParsedSnippet/text``.
    public let range: NSRange

    public init(index: Int, range: NSRange) {
        self.index = index
        self.range = range
    }
}

/// Snippet text with its syntax removed, plus the tab stops found in it.
public struct ParsedSnippet: Equatable, Sendable {
    /// The text to insert.
    public let text: String
    /// Tab stops in the order they appear in `text`. An index can appear more than once (mirrors).
    public let tabStops: [SnippetTabStop]

    public init(text: String, tabStops: [SnippetTabStop]) {
        self.text = text
        self.tabStops = tabStops
    }

    /// Tab-stop ranges grouped by index in navigation order: `1, 2, …`, then `$0`.
    ///
    /// When the snippet has no `$0`, the last group is an empty range at the end of `text`.
    public var navigationGroups: [[NSRange]] {
        let numbered = Set(tabStops.map(\.index).filter { $0 > 0 }).sorted()
        var groups = numbered.map { index in
            tabStops.filter { $0.index == index }.map(\.range).sorted { $0.location < $1.location }
        }
        if let final = tabStops.first(where: { $0.index == 0 }) {
            groups.append([NSRange(location: final.range.location, length: 0)])
        } else {
            groups.append([NSRange(location: (text as NSString).length, length: 0)])
        }
        return groups
    }

    /// `true` when the snippet has at least one numbered tab stop to move through.
    public var hasPlaceholders: Bool {
        tabStops.contains { $0.index > 0 }
    }
}

/// Parses the LSP / TextMate snippet syntax.
///
/// Supports `$1`, `${1}`, `${1:placeholder}` (nested), `${1|one,two|}` choices (the first choice is
/// inserted), `$0`, variables (`$NAME`, `${NAME:default}`, replaced by their default or nothing),
/// transforms (dropped), and `\$`, `\}`, `\\` escapes. Unrecognized `$` sequences are kept as text.
public enum SnippetParser {
    /// Parses `snippet` into plain text and tab stops.
    public static func parse(_ snippet: String) -> ParsedSnippet {
        var parser = Parser(characters: Array(snippet))
        parser.parseAny(until: nil)
        return ParsedSnippet(text: parser.output, tabStops: parser.tabStops)
    }

    /// Returns `snippet` with its syntax removed.
    public static func plainText(_ snippet: String) -> String {
        parse(snippet).text
    }
}

private struct Parser {
    let characters: [Character]
    var index = 0
    var output = ""
    /// Length of `output` in UTF-16 code units.
    var outputLength = 0
    var tabStops: [SnippetTabStop] = []

    init(characters: [Character]) {
        self.characters = characters
    }

    private var current: Character? {
        index < characters.count ? characters[index] : nil
    }

    private mutating func append(_ character: Character) {
        output.append(character)
        outputLength += character.utf16.count
    }

    private mutating func append(_ string: String) {
        output += string
        outputLength += string.utf16.count
    }

    /// Parses text and snippet elements until `terminator` (unescaped) or the end of input.
    /// The terminator itself is not consumed.
    mutating func parseAny(until terminator: Character?) {
        while let character = current {
            if character == "\\", index + 1 < characters.count,
               "$}\\".contains(characters[index + 1]) {
                append(characters[index + 1])
                index += 2
                continue
            }
            if let terminator, character == terminator {
                return
            }
            if character == "$", parseDollar() {
                continue
            }
            append(character)
            index += 1
        }
    }

    /// Parses an element starting at `$`. Restores the position and returns `false` when the
    /// sequence is not valid snippet syntax.
    private mutating func parseDollar() -> Bool {
        let start = index
        let saved = (output: output, outputLength: outputLength, tabStops: tabStops)
        defer {
            if index == start {
                (output, outputLength, tabStops) = saved
            }
        }
        index += 1
        if let number = readInt() {
            addTabStop(number, range: NSRange(location: outputLength, length: 0))
            return true
        }
        if readVariableName() != nil {
            return true
        }
        guard current == "{" else {
            index = start
            return false
        }
        index += 1
        if let number = readInt() {
            if parseTabStopBody(number) { return true }
        } else if readVariableName() != nil {
            if parseVariableBody() { return true }
        }
        index = start
        return false
    }

    /// Parses what follows `${n`.
    private mutating func parseTabStopBody(_ number: Int) -> Bool {
        let placeholderStart = outputLength
        switch current {
        case "}":
            index += 1
            addTabStop(number, range: NSRange(location: placeholderStart, length: 0))
            return true
        case ":":
            index += 1
            parseAny(until: "}")
            guard current == "}" else { return false }
            index += 1
            addTabStop(number, range: NSRange(location: placeholderStart, length: outputLength - placeholderStart))
            return true
        case "|":
            index += 1
            guard let choices = readChoices() else { return false }
            append(choices.first ?? "")
            addTabStop(number, range: NSRange(location: placeholderStart, length: outputLength - placeholderStart))
            return true
        case "/":
            guard skipTransform() else { return false }
            addTabStop(number, range: NSRange(location: placeholderStart, length: 0))
            return true
        default:
            return false
        }
    }

    /// Parses what follows `${NAME`. Variables resolve to their default value.
    private mutating func parseVariableBody() -> Bool {
        switch current {
        case "}":
            index += 1
            return true
        case ":":
            index += 1
            parseAny(until: "}")
            guard current == "}" else { return false }
            index += 1
            return true
        case "/":
            return skipTransform()
        default:
            return false
        }
    }

    /// Reads `a,b,c|}` after `${n|`.
    private mutating func readChoices() -> [String]? {
        var choices: [String] = []
        var choice = ""
        while let character = current {
            if character == "\\", index + 1 < characters.count, ",|\\$}".contains(characters[index + 1]) {
                choice.append(characters[index + 1])
                index += 2
                continue
            }
            if character == "," {
                choices.append(choice)
                choice = ""
                index += 1
                continue
            }
            if character == "|" {
                guard index + 1 < characters.count, characters[index + 1] == "}" else { return nil }
                choices.append(choice)
                index += 2
                return choices
            }
            choice.append(character)
            index += 1
        }
        return nil
    }

    /// Skips `/regex/format/options}`.
    private mutating func skipTransform() -> Bool {
        var slashes = 0
        while let character = current {
            if character == "\\", index + 1 < characters.count {
                index += 2
                continue
            }
            if character == "/" {
                slashes += 1
            } else if character == "}", slashes >= 3 {
                index += 1
                return true
            }
            index += 1
        }
        return false
    }

    private mutating func readInt() -> Int? {
        let start = index
        while let character = current, character.isASCII, character.isNumber {
            index += 1
        }
        guard index > start else { return nil }
        return Int(String(characters[start..<index]))
    }

    private mutating func readVariableName() -> String? {
        guard let first = current, first == "_" || (first.isASCII && first.isLetter) else { return nil }
        let start = index
        while let character = current,
              character == "_" || (character.isASCII && (character.isLetter || character.isNumber)) {
            index += 1
        }
        return String(characters[start..<index])
    }

    private mutating func addTabStop(_ number: Int, range: NSRange) {
        tabStops.append(SnippetTabStop(index: number, range: range))
    }
}
