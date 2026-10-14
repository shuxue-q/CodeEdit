//
//  YAMLReader.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

/// A node of the YAML subset ``YAMLReader`` understands.
indirect enum YAMLNode: Equatable, Sendable {
    case null
    case scalar(String)
    case sequence([YAMLNode])
    case mapping(YAMLMapping)

    /// The scalar text, when the node is a scalar.
    var string: String? {
        if case .scalar(let value) = self { return value }
        return nil
    }

    /// The scalar read as a Boolean (`true`/`false`, `yes`/`no`, `on`/`off`).
    var boolean: Bool? {
        switch string?.lowercased() {
        case "true", "yes", "on": true
        case "false", "no", "off": false
        default: nil
        }
    }

    /// The elements, when the node is a sequence.
    var sequence: [YAMLNode]? {
        if case .sequence(let value) = self { return value }
        return nil
    }

    /// The mapping, when the node is one.
    var mapping: YAMLMapping? {
        if case .mapping(let value) = self { return value }
        return nil
    }

    /// The scalars of a sequence, or a lone scalar as a one-element list.
    var strings: [String] {
        if let string { return [string] }
        return sequence?.compactMap(\.string) ?? []
    }

    /// Looks up `key` when the node is a mapping.
    subscript(key: String) -> YAMLNode? {
        mapping?[key]
    }
}

/// A YAML mapping that keeps its keys in file order.
struct YAMLMapping: Equatable, Sendable {
    /// The keys in file order.
    private(set) var keys: [String] = []
    private var storage: [String: YAMLNode] = [:]

    /// The value of `key`; a repeated key keeps its first position and its last value.
    subscript(key: String) -> YAMLNode? {
        get { storage[key] }
        set {
            guard let newValue else { return }
            if storage.updateValue(newValue, forKey: key) == nil { keys.append(key) }
        }
    }

    /// The key/value pairs in file order.
    var entries: [(key: String, value: YAMLNode)] {
        keys.compactMap { key in storage[key].map { (key, $0) } }
    }
}

/// Reads the block-style YAML used by `pubspec.yaml`, `analysis_options.yaml` and `.metadata`.
///
/// Supports block mappings and sequences (including `- key: value` items), single-line flow
/// mappings and sequences, plain and quoted scalars, comments, block scalars (`|`, `>`) and the
/// first document of a stream. Anchors, aliases, tags and multi-line flow collections are not
/// interpreted; such values read as plain text.
enum YAMLReader {
    /// Parses YAML text into a node; an empty document is ``YAMLNode/null``.
    static func parse(_ text: String) -> YAMLNode {
        var parser = Parser(lines: Self.lines(of: text))
        return parser.parseDocument()
    }

    /// Reads and parses the file at `url`, or returns `nil` when it cannot be read.
    static func read(at url: URL) -> YAMLNode? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// One meaningful line: its indentation, its content without the comment, and the raw text
    /// (block scalars keep comments and spacing).
    fileprivate struct Line {
        var indent: Int
        var content: String
        var raw: Substring
    }

    private static func lines(of text: String) -> [Line] {
        var result: [Line] = []
        var started = false
        // `\r\n` is a single Character, so split on any newline rather than on "\n".
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let indent = raw.prefix { $0 == " " }.count
            let content = stripComment(raw.dropFirst(indent)).trimmingCharacters(in: .whitespaces)
            if indent == 0 && (content == "---" || content == "...") {
                if started { break }
                continue
            }
            if !content.isEmpty { started = true }
            result.append(Line(indent: indent, content: content, raw: raw))
        }
        return result
    }

    /// Removes a trailing `# comment`, ignoring `#` inside quotes or glued to a word.
    fileprivate static func stripComment(_ line: Substring) -> Substring {
        var quote: Character?
        var previous: Character = " "
        for index in line.indices {
            let character = line[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "#" && (previous == " " || previous == "\t") {
                return line[..<index]
            }
            previous = character
        }
        return line
    }

    /// Splits `key: value` at the first unquoted `:` followed by a space or the line end.
    fileprivate static func splitKeyValue(_ content: String) -> (String, String)? {
        var quote: Character?
        var depth = 0
        var index = content.startIndex
        while index < content.endIndex {
            let character = content[index]
            let next = content.index(after: index)
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "{" || character == "[" {
                depth += 1
            } else if character == "}" || character == "]" {
                depth -= 1
            } else if character == ":" && depth == 0 && (next == content.endIndex || content[next] == " ") {
                let key = unquote(content[..<index].trimmingCharacters(in: .whitespaces))
                let value = content[next...].trimmingCharacters(in: .whitespaces)
                return key.isEmpty ? nil : (key, value)
            }
            index = next
        }
        return nil
    }

    fileprivate static func isSequenceItem(_ content: String) -> Bool {
        content.hasPrefix("-") && (content.count == 1 || content.dropFirst().first == " ")
    }

    fileprivate static func isBlockScalarIndicator(_ value: String) -> Bool {
        guard let first = value.first, first == "|" || first == ">" else { return false }
        return value.dropFirst().allSatisfy { $0 == "-" || $0 == "+" || $0.isNumber }
    }

    /// Reads an inline value: a flow collection, a quoted scalar, or a plain scalar.
    fileprivate static func inlineValue(_ text: String) -> YAMLNode {
        let text = text.trimmingCharacters(in: .whitespaces)
        if text.isEmpty || text == "~" || text == "null" { return .null }
        if text.hasPrefix("{") && text.hasSuffix("}") {
            var mapping = YAMLMapping()
            for entry in splitFlow(String(text.dropFirst().dropLast())) {
                if let (key, value) = splitKeyValue(entry) {
                    mapping[key] = inlineValue(value)
                } else if !entry.isEmpty {
                    mapping[unquote(entry)] = .null
                }
            }
            return .mapping(mapping)
        }
        if text.hasPrefix("[") && text.hasSuffix("]") {
            return .sequence(splitFlow(String(text.dropFirst().dropLast())).filter { !$0.isEmpty }.map(inlineValue))
        }
        return .scalar(unquote(text))
    }

    /// Splits flow collection content at top-level commas.
    private static func splitFlow(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        for character in text {
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "{" || character == "[" {
                depth += 1
            } else if character == "}" || character == "]" {
                depth -= 1
            } else if character == "," && depth == 0 {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                continue
            }
            current.append(character)
        }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        return parts
    }

    fileprivate static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == "\"" || first == "'",
              value.last == first else {
            return value
        }
        let inner = String(value.dropFirst().dropLast())
        return first == "'" ? inner.replacingOccurrences(of: "''", with: "'") : inner
    }
}

// MARK: - Parser

private struct Parser {
    var lines: [YAMLReader.Line]
    var index = 0

    init(lines: [YAMLReader.Line]) {
        self.lines = lines
    }

    mutating func parseDocument() -> YAMLNode {
        skipBlankLines()
        guard index < lines.count else { return .null }
        let node = parseBlock(indent: lines[index].indent)
        return node
    }

    private mutating func skipBlankLines() {
        while index < lines.count && lines[index].content.isEmpty { index += 1 }
    }

    /// The indentation of the next meaningful line, or `nil` at the end.
    private mutating func nextIndent() -> Int? {
        skipBlankLines()
        return index < lines.count ? lines[index].indent : nil
    }

    private mutating func parseBlock(indent: Int) -> YAMLNode {
        guard nextIndent() != nil else { return .null }
        if YAMLReader.isSequenceItem(lines[index].content) {
            return parseSequence(indent: indent)
        }
        if YAMLReader.splitKeyValue(lines[index].content) == nil {
            // A plain or flow scalar spanning the block; YAML's multi-line plain scalars are joined.
            var parts: [String] = []
            while let next = nextIndent(), next >= indent {
                parts.append(lines[index].content)
                index += 1
            }
            return parts.count == 1 ? YAMLReader.inlineValue(parts[0]) : .scalar(parts.joined(separator: " "))
        }
        return parseMapping(indent: indent)
    }

    private mutating func parseMapping(indent: Int) -> YAMLNode {
        var mapping = YAMLMapping()
        while let next = nextIndent(), next >= indent {
            // Lines indented deeper than expected without an owner are skipped, not misread.
            if next > indent {
                index += 1
                continue
            }
            let line = lines[index]
            guard !YAMLReader.isSequenceItem(line.content),
                  let (key, value) = YAMLReader.splitKeyValue(line.content) else {
                break
            }
            index += 1
            mapping[key] = parseValue(value, ownerIndent: indent)
        }
        return .mapping(mapping)
    }

    private mutating func parseSequence(indent: Int) -> YAMLNode {
        var items: [YAMLNode] = []
        while let next = nextIndent(), next == indent, YAMLReader.isSequenceItem(lines[index].content) {
            let line = lines[index]
            let afterDash = line.content.dropFirst()
            let spaces = afterDash.prefix { $0 == " " }.count
            let rest = String(afterDash.dropFirst(spaces))
            if rest.isEmpty {
                index += 1
                if let childIndent = nextIndent(), childIndent > indent {
                    items.append(parseBlock(indent: childIndent))
                } else {
                    items.append(.null)
                }
            } else if YAMLReader.isSequenceItem(rest) || YAMLReader.splitKeyValue(rest) != nil {
                // `- key: value` starts a mapping (or a nested sequence) at the item's column.
                lines[index] = YAMLReader.Line(indent: indent + 1 + spaces, content: rest, raw: line.raw)
                items.append(parseBlock(indent: indent + 1 + spaces))
            } else {
                index += 1
                items.append(YAMLReader.inlineValue(rest))
            }
        }
        return .sequence(items)
    }

    /// The value of `key: value`, reading the following block when the value is empty.
    private mutating func parseValue(_ value: String, ownerIndent: Int) -> YAMLNode {
        if YAMLReader.isBlockScalarIndicator(value) {
            return .scalar(readBlockScalar(ownerIndent: ownerIndent, folded: value.hasPrefix(">")))
        }
        guard value.isEmpty else { return YAMLReader.inlineValue(value) }
        guard let childIndent = nextIndent() else { return .null }
        if childIndent > ownerIndent {
            return parseBlock(indent: childIndent)
        }
        // YAML allows a sequence at the key's own indentation: `key:\n- a\n- b`.
        if childIndent == ownerIndent && YAMLReader.isSequenceItem(lines[index].content) {
            return parseSequence(indent: childIndent)
        }
        return .null
    }

    private mutating func readBlockScalar(ownerIndent: Int, folded: Bool) -> String {
        var collected: [String] = []
        var contentIndent: Int?
        while index < lines.count {
            let line = lines[index]
            let isBlank = line.raw.allSatisfy(\.isWhitespace)
            if !isBlank && line.indent <= ownerIndent { break }
            index += 1
            if isBlank {
                collected.append("")
                continue
            }
            let indent = contentIndent ?? line.indent
            contentIndent = indent
            collected.append(String(line.raw.dropFirst(min(indent, line.indent))))
        }
        while collected.last == "" { collected.removeLast() }
        return collected.joined(separator: folded ? " " : "\n")
    }
}
