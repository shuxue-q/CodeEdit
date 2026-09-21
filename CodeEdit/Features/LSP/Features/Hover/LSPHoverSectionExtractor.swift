//
//  LSPHoverSectionExtractor.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/16/26.
//

import Foundation

/// Helpers for extracting doc sections, parameters, returns, callouts, and symbols.
enum LSPHoverSectionExtractor {
    /// Temporary representation of a parsed parameter line.
    struct ParsedParam: Equatable {
        var name: String
        var type: String?
        var description: String
    }

    /// Determines if a line is a parameter section header.
    static func isParametersHeader(_ line: String) -> Bool {
        let lower = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "-*# \t"))
        let headers: Set<String> = [
            "parameters:", "parameters", "args:", "args", "arguments:", "arguments", "params:", "params"
        ]
        return headers.contains(lower)
    }

    /// Attempts to parse a parameter line in various documentation styles.
    static func parseParameterLine(_ line: String, inParametersSection: Bool = false) -> ParsedParam? {
        if line.hasPrefix("@param") || line.hasPrefix("\\param") {
            return parseDoxygenParam(line)
        }
        if line.hasPrefix("- Parameter ") || line.hasPrefix("* Parameter ") {
            return parseSwiftParam(line)
        }
        if line.hasPrefix(":param ") {
            return parseSphinxParam(line)
        }
        if inParametersSection {
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                return parseBulletParam(line)
            }
            if line.contains(":") {
                return parseColonParam(line)
            }
        }
        return nil
    }

    private static func parseDoxygenParam(_ line: String) -> ParsedParam? {
        var text = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("["), let closeBracket = text.firstIndex(of: "]") {
            text = String(text[closeBracket...].dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        var type: String?
        if text.hasPrefix("{"), let closeBrace = text.firstIndex(of: "}") {
            type = String(text[text.index(after: text.startIndex)..<closeBrace]).trimmingCharacters(in: .whitespaces)
            text = String(text[closeBrace...].dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        let parts = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard let rawName = parts.first else { return nil }
        var name = cleanIdentifier(rawName)
        if name.hasPrefix("[") && name.hasSuffix("]") {
            name = String(name.dropFirst().dropLast())
            if let eqIdx = name.firstIndex(of: "=") {
                name = String(name[..<eqIdx])
            }
        }
        var desc = parts.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if desc.hasPrefix("- ") {
            desc = String(desc.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        } else if desc.hasPrefix(": ") {
            desc = String(desc.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return ParsedParam(name: cleanIdentifier(name), type: type, description: desc)
    }

    private static func parseSphinxParam(_ line: String) -> ParsedParam? {
        let content = line.dropFirst(7).trimmingCharacters(in: .whitespaces)
        guard let colonIdx = content.firstIndex(of: ":") else { return nil }
        let namePart = String(content[..<colonIdx]).trimmingCharacters(in: .whitespaces)
        let desc = String(content[colonIdx...].dropFirst()).trimmingCharacters(in: .whitespaces)
        let words = namePart.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if words.count >= 2 {
            let name = cleanIdentifier(words.last!)
            let type = words.dropLast().joined(separator: " ")
            return ParsedParam(name: name, type: type, description: desc)
        } else if let name = words.first {
            return ParsedParam(name: cleanIdentifier(name), type: nil, description: desc)
        }
        return nil
    }

    private static func parseSwiftParam(_ line: String) -> ParsedParam? {
        let text = line.dropFirst(12).trimmingCharacters(in: .whitespaces)
        guard let colonIdx = text.firstIndex(of: ":") else { return nil }
        let name = String(text[..<colonIdx]).trimmingCharacters(in: .whitespaces)
        let desc = String(text[colonIdx...].dropFirst()).trimmingCharacters(in: .whitespaces)
        return ParsedParam(name: cleanIdentifier(name), type: nil, description: desc)
    }

    private static func createParam(namePart: String, description: String) -> ParsedParam? {
        let parsed = parseNameAndType(namePart)
        guard isValidIdentifier(parsed.name) && !isSectionHeader(parsed.name) else { return nil }
        return ParsedParam(name: parsed.name, type: parsed.type, description: description)
    }

    private static func parseBulletParam(_ line: String) -> ParsedParam? {
        let content = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
        if let colonIdx = content.firstIndex(of: ":") {
            let name = String(content[..<colonIdx]).trimmingCharacters(in: .whitespaces)
            let desc = String(content[colonIdx...].dropFirst()).trimmingCharacters(in: .whitespaces)
            return createParam(namePart: name, description: desc)
        }
        if let hyphenIdx = content.range(of: " - ") {
            let name = String(content[..<hyphenIdx.lowerBound]).trimmingCharacters(in: .whitespaces)
            let desc = String(content[hyphenIdx.upperBound...]).trimmingCharacters(in: .whitespaces)
            return createParam(namePart: name, description: desc)
        }
        return nil
    }

    private static func parseColonParam(_ line: String) -> ParsedParam? {
        guard let colonIdx = line.firstIndex(of: ":") else { return nil }
        let name = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces)
        let desc = String(line[colonIdx...].dropFirst()).trimmingCharacters(in: .whitespaces)
        return createParam(namePart: name, description: desc)
    }

    private static func extractPrefixed(from line: String, prefixes: [String]) -> String? {
        for prefix in prefixes where line.hasPrefix(prefix) {
            return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Extracts returns text from a line if present.
    static func extractReturns(_ line: String) -> String? {
        extractPrefixed(from: line, prefixes: [
            "- Returns:", "- Return:", "* Returns:", "* Return:", "@return", "@returns",
            "\\return", "\\returns", "Returns:", "Return:", "### Returns", "## Returns",
            "# Returns", "### Return", "## Return", "# Return", ":returns:", ":return:",
            ":returns ", ":return ",
            ":rtype:", "Yields:", "Yield:", "- Yields:", "- Yield:", "@yield", "@yields"
        ])
    }

    /// Extracts throws text from a line if present.
    static func extractThrows(_ line: String) -> String? {
        extractPrefixed(from: line, prefixes: [
            "- Throws:", "- Throw:", "* Throws:", "* Throw:", "@throws", "@throw",
            "\\throws", "\\throw", "Throws:", "Throw:", "Raises:", "- Raises:",
            ":raises:", ":raise:", ":raises ", ":raise ", "@raise",
            "# Errors", "## Errors", "### Errors", "# Panics", "## Panics", "### Panics"
        ])
    }

    private struct CalloutDef {
        var prefixes: [String]
        var kind: LSPHoverCallout.Kind
        var title: String
    }

    /// Extracts callouts like Note, Warning, Deprecated, etc.
    static func extractCallout(_ line: String) -> LSPHoverCallout? {
        let defs: [CalloutDef] = [
            CalloutDef(
                prefixes: ["- Warning:", "Warning:", "@warning", "\\warning", "- WARNING:"],
                kind: .warning,
                title: "Warning"
            ),
            CalloutDef(
                prefixes: ["- Deprecated:", "Deprecated:", "@deprecated", "\\deprecated"],
                kind: .deprecated,
                title: "Deprecated"
            ),
            CalloutDef(
                prefixes: ["- Important:", "Important:", "- IMPORTANT:"],
                kind: .important,
                title: "Important"
            ),
            CalloutDef(
                prefixes: ["- Note:", "Note:", "@note", "\\note", "- NOTE:"],
                kind: .note,
                title: "Note"
            ),
            CalloutDef(
                prefixes: ["- See Also:", "See Also:", "@see", "\\see"],
                kind: .seeAlso,
                title: "See Also"
            )
        ]
        for def in defs {
            for prefix in def.prefixes where line.hasPrefix(prefix) {
                let msg = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                return LSPHoverCallout(kind: def.kind, title: def.title, message: msg)
            }
        }
        return nil
    }

    /// Cleans parameter identifier from backticks or punctuation.
    static func cleanIdentifier(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: "`*: "))
    }

    /// Parses name and optional type: e.g. "count (Int)" -> ("count", "Int").
    static func parseNameAndType(_ text: String) -> (name: String, type: String?) {
        let clean = cleanIdentifier(text)
        if let open = clean.firstIndex(of: "("), let close = clean.lastIndex(of: ")"), open < close {
            let name = String(clean[..<open]).trimmingCharacters(in: .whitespaces)
            let type = String(clean[clean.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            return (name, type.isEmpty ? nil : type)
        }
        return (clean, nil)
    }

    /// Checks if a string is a valid identifier.
    static func isValidIdentifier(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 64 else { return false }
        if text.hasPrefix("operator") { return true }
        var candidate = text
        if candidate.hasPrefix("~") { candidate = String(candidate.dropFirst()) }
        guard !candidate.isEmpty else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$."))
        return candidate.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func isSectionHeader(_ text: String) -> Bool {
        let lower = text.lowercased()
        let headers: Set<String> = [
            "parameters", "returns", "throws", "note", "warning", "example",
            "usage", "details", "arguments", "args"
        ]
        return headers.contains(lower)
    }
}
