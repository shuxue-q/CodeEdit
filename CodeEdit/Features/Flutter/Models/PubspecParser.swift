//
//  PubspecParser.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

/// The parts of a `pubspec.yaml` CodeEdit needs to recognize a Flutter project.
struct Pubspec: Equatable, Sendable {
    /// The package name (`name:`).
    var name: String?
    /// The package version (`version:`), such as `1.2.0+3`.
    var version: String?
    /// Whether `dependencies` contains `flutter` (normally `flutter: sdk: flutter`).
    var dependsOnFlutter = false
    /// Platforms whose `flutter.plugin.platforms.<platform>.ffiPlugin` is `true`, in file order.
    var ffiPluginPlatforms: [String] = []
}

/// A minimal, line-based reader for the few `pubspec.yaml` keys CodeEdit uses.
///
/// It understands block mappings, comments, quoted scalars, single-line flow mappings
/// (`macos: { ffiPlugin: true }`) and skips block scalars (`description: |`). It is not a YAML
/// parser: anchors, multi-line flow collections and documents after the first are ignored.
enum PubspecParser {
    /// The pubspec file name.
    static let fileName = "pubspec.yaml"

    /// Parses the contents of a `pubspec.yaml` file.
    /// - Parameter text: The file contents.
    /// - Returns: The recognized keys; missing keys stay `nil` or empty.
    static func parse(_ text: String) -> Pubspec {
        var pubspec = Pubspec()
        var stack: [(indent: Int, key: String)] = []
        /// Lines indented deeper than this belong to a block scalar and are skipped.
        var blockScalarIndent: Int?

        // `\r\n` is a single Character, so split on any newline rather than on "\n".
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let indent = line.prefix { $0 == " " }.count
            let content = stripComment(line.dropFirst(indent)).trimmingCharacters(in: .whitespaces)
            if content.isEmpty { continue }
            if let scalarIndent = blockScalarIndent {
                if indent > scalarIndent { continue }
                blockScalarIndent = nil
            }
            if indent == 0 && (content == "---" || content == "...") {
                if content == "..." || pubspec != Pubspec() { break }
                continue
            }
            while let last = stack.last, last.indent >= indent { stack.removeLast() }
            // Sequence items never carry the keys read here.
            guard !isSequenceItem(content), let (key, value) = splitKeyValue(content) else { continue }
            let path = stack.map(\.key) + [key]

            if value.isEmpty {
                stack.append((indent, key))
                continue
            }
            if isBlockScalarIndicator(value) {
                blockScalarIndent = indent
                continue
            }
            apply(path: path, value: value, to: &pubspec)
        }
        return pubspec
    }

    // MARK: - Interpretation

    private static func apply(path: [String], value: String, to pubspec: inout Pubspec) {
        switch path {
        case ["name"]:
            pubspec.name = unquote(value)
        case ["version"]:
            pubspec.version = unquote(value)
        case ["dependencies", "flutter", "sdk"]:
            if unquote(value) == "flutter" { pubspec.dependsOnFlutter = true }
        case ["dependencies", "flutter"]:
            // `flutter: { sdk: flutter }`
            if flowMapping(value)["sdk"] == "flutter" { pubspec.dependsOnFlutter = true }
        default:
            applyPluginPlatform(path: path, value: value, to: &pubspec)
        }
    }

    /// Records `flutter.plugin.platforms.<platform>.ffiPlugin: true`, in block or flow style.
    private static func applyPluginPlatform(path: [String], value: String, to pubspec: inout Pubspec) {
        guard path.count >= 4, Array(path.prefix(3)) == ["flutter", "plugin", "platforms"] else { return }
        let platform = path[3]
        let isFFIPlugin = switch path.count {
        case 4: flowMapping(value)["ffiPlugin"] == "true"
        case 5: path[4] == "ffiPlugin" && unquote(value) == "true"
        default: false
        }
        if isFFIPlugin && !pubspec.ffiPluginPlatforms.contains(platform) {
            pubspec.ffiPluginPlatforms.append(platform)
        }
    }

    // MARK: - Lexing

    /// Removes a trailing `# comment`, ignoring `#` inside quotes or glued to a word.
    private static func stripComment(_ line: Substring) -> Substring {
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
    private static func splitKeyValue(_ content: String) -> (String, String)? {
        var quote: Character?
        var index = content.startIndex
        while index < content.endIndex {
            let character = content[index]
            let next = content.index(after: index)
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ":" && (next == content.endIndex || content[next] == " ") {
                let key = unquote(content[..<index].trimmingCharacters(in: .whitespaces))
                let value = content[next...].trimmingCharacters(in: .whitespaces)
                return key.isEmpty ? nil : (key, value)
            }
            index = next
        }
        return nil
    }

    private static func isSequenceItem(_ content: String) -> Bool {
        content.hasPrefix("-") && (content.count == 1 || content.dropFirst().first == " ")
    }

    private static func isBlockScalarIndicator(_ value: String) -> Bool {
        guard let first = value.first, first == "|" || first == ">" else { return false }
        return value.dropFirst().allSatisfy { $0 == "-" || $0 == "+" || $0.isNumber }
    }

    /// Reads a single-line flow mapping such as `{ sdk: flutter }` into its scalar entries.
    private static func flowMapping(_ value: String) -> [String: String] {
        guard value.hasPrefix("{"), value.hasSuffix("}") else { return [:] }
        var entries: [String: String] = [:]
        for entry in value.dropFirst().dropLast().split(separator: ",") {
            let entry = entry.trimmingCharacters(in: .whitespaces)
            guard let (key, value) = splitKeyValue(entry) else { continue }
            entries[key] = unquote(value)
        }
        return entries
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == "\"" || first == "'",
              value.last == first else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }
}
