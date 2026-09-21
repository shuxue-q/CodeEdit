//
//  LSPHoverParser.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/16/26.
//

import Foundation

/// Parses raw hover documentation strings into structured ``LSPHoverDocumentation``.
enum LSPHoverParser {
    /// Parses the raw markdown or text into structured documentation.
    static func parse(content: String, fallbackLanguage: String? = nil) -> LSPHoverDocumentation {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return LSPHoverDocumentation()
        }

        var remainingText = normalizeDividers(trimmed)
        var declaration: LSPHoverDeclaration?

        // Check if there is a code block at the beginning or immediately following a markdown header (e.g. Clangd/Rust)
        if let codeBlockDecl = extractLeadingCodeBlock(&remainingText, fallbackLanguage: fallbackLanguage) {
            declaration = codeBlockDecl
        } else {
            declaration = extractLeadingSignature(&remainingText, fallbackLanguage: fallbackLanguage)
        }

        stripLeadingDividers(&remainingText)

        var documentation = LSPHoverDocumentation(declaration: declaration)
        let state = LSPHoverBodyParser()
        state.parse(text: remainingText, into: &documentation)
        return documentation
    }

    // MARK: - Declaration Extraction

    private struct CodeBlockResult {
        var declaration: LSPHoverDeclaration
        var remaining: String
    }

    /// Extracts a leading markdown code block as the declaration.
    /// Handles headers preceding code blocks (e.g. Clangd `### function foo`) and multi-block headers.
    static func extractLeadingCodeBlock(
        _ text: inout String,
        fallbackLanguage: String?
    ) -> LSPHoverDeclaration? {
        var working = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip leading markdown header lines if followed by a code block
        while working.hasPrefix("#") {
            if let newlineIdx = working.firstIndex(of: "\n") {
                let candidate = String(working[newlineIdx...].dropFirst()).trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                if candidate.hasPrefix("```") || candidate.hasPrefix("#") {
                    working = candidate
                } else {
                    break
                }
            } else {
                break
            }
        }

        guard working.hasPrefix("```") else { return nil }

        guard let firstBlock = parseSingleCodeBlock(from: working, fallbackLanguage: fallbackLanguage) else {
            return nil
        }

        var selectedDecl = firstBlock.declaration
        var remainingAfterDecl = firstBlock.remaining

        // Check if there is an immediately adjacent second code block that represents a better declaration
        // (e.g. rust-analyzer providing crate path first, then function declaration)
        if remainingAfterDecl.hasPrefix("```"),
           let secondBlock = parseSingleCodeBlock(from: remainingAfterDecl, fallbackLanguage: fallbackLanguage) {
            let firstHasDecl = containsDeclarationKeyword(firstBlock.declaration.rawCode)
            let secondHasDecl = containsDeclarationKeyword(secondBlock.declaration.rawCode)
            if !firstHasDecl && secondHasDecl {
                selectedDecl = secondBlock.declaration
                remainingAfterDecl = secondBlock.remaining
            }
        }

        text = remainingAfterDecl
        return selectedDecl
    }

    private static func parseSingleCodeBlock(
        from text: String,
        fallbackLanguage: String?
    ) -> CodeBlockResult? {
        guard text.hasPrefix("```") else { return nil }
        let afterOpening = text.dropFirst(3)
        guard let firstNewlineIdx = afterOpening.firstIndex(of: "\n") else { return nil }

        let langSpecifier = String(afterOpening[..<firstNewlineIdx]).trimmingCharacters(in: .whitespaces)
        let codeAndRest = String(afterOpening[firstNewlineIdx...].dropFirst())

        guard let closingIdx = codeAndRest.range(of: "```") else { return nil }

        let rawCode = String(codeAndRest[..<closingIdx.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let remaining = String(codeAndRest[closingIdx.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        let language = langSpecifier.isEmpty ? fallbackLanguage : langSpecifier
        let formatted = LSPHoverDeclarationFormatter.format(code: rawCode)
        let symbolName = LSPHoverSectionExtractor.extractSymbolName(from: rawCode)

        let decl = LSPHoverDeclaration(
            code: formatted,
            rawCode: rawCode,
            language: language,
            symbolName: symbolName
        )
        return CodeBlockResult(declaration: decl, remaining: remaining)
    }

    private static func containsDeclarationKeyword(_ code: String) -> Bool {
        let keywords = [
            "fn ", "func ", "def ", "pub ", "struct ", "enum ", "class ", "trait ",
            "type ", "let ", "var ", "const ", "namespace ", "template", "using ",
            "typedef ", "extern ", "inline ", "constexpr ", "consteval ", "constinit ",
            "concept ", "auto ", "union ", "virtual ", "explicit ", "friend "
        ]
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("(") || trimmed.hasPrefix("~") { return true }
        return keywords.contains { trimmed.contains($0) }
    }

    /// Extracts a leading plain signature line if it matches declaration keywords.
    static func extractLeadingSignature(
        _ text: inout String,
        fallbackLanguage: String?
    ) -> LSPHoverDeclaration? {
        let lines = text.components(separatedBy: "\n")
        guard let firstLine = lines.first else { return nil }
        let trimmedFirst = firstLine.trimmingCharacters(in: .whitespaces)
        guard !trimmedFirst.isEmpty else { return nil }

        guard isDeclarationStarter(trimmedFirst) else { return nil }

        var declLines: [String] = [trimmedFirst]
        var count = 1

        if !isSignatureComplete(trimmedFirst) {
            for line in lines.dropFirst() {
                let item = line.trimmingCharacters(in: .whitespaces)
                if item.isEmpty || isDividerLine(item) || item.hasPrefix("@")
                    || item.hasPrefix("//") || item.hasPrefix("#") {
                    break
                }
                declLines.append(item)
                count += 1
                if isSignatureComplete(declLines.joined(separator: " ")) {
                    break
                }
            }
        }

        let rawCode = declLines.joined(separator: "\n")
        let remainingLines = lines.dropFirst(count)
        text = remainingLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        let formatted = LSPHoverDeclarationFormatter.format(code: rawCode)
        let symbolName = LSPHoverSectionExtractor.extractSymbolName(from: rawCode)

        return LSPHoverDeclaration(
            code: formatted,
            rawCode: rawCode,
            language: fallbackLanguage,
            symbolName: symbolName
        )
    }

    private static func isDeclarationStarter(_ trimmed: String) -> Bool {
        let starters = [
            "func ", "def ", "fn ", "pub fn ", "sub ", "void ", "int ", "char ",
            "float ", "double ", "bool ", "class ", "struct ", "enum ", "protocol ",
            "interface ", "type ", "typealias ", "var ", "let ", "const ", "val ",
            "public ", "private ", "internal ", "open ", "static ", "final ",
            "namespace ", "template", "using ", "typedef ", "extern ", "inline ",
            "constexpr ", "consteval ", "constinit ", "concept ", "auto ", "union ",
            "virtual ", "explicit ", "friend ", "mutable ", "volatile ", "override "
        ]

        if starters.contains(where: { trimmed.hasPrefix($0) }) {
            return true
        }

        if trimmed.hasPrefix("~") && trimmed.contains("(") {
            return true
        }

        if trimmed.contains("::") && !trimmed.contains("://") && isValidQualifiedDeclaration(trimmed) {
            return true
        }

        if isAttributeStarter(trimmed) {
            return true
        }

        if isConstructorDeclaration(trimmed) {
            return true
        }

        return false
    }

    private static func isAttributeStarter(_ trimmed: String) -> Bool {
        if trimmed.hasPrefix("[[") { return true }
        guard trimmed.hasPrefix("@") else { return false }
        let docTags: Set<String> = [
            "@param", "@return", "@returns", "@throw", "@throws", "@note",
            "@warning", "@see", "@deprecated", "@brief", "@details", "@author"
        ]
        return !docTags.contains { trimmed.hasPrefix($0) }
    }

    private static func isValidQualifiedDeclaration(_ text: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_:~<>*&"))
        guard let first = text.first, first.isLetter || first == "_" || first == "~" else { return false }
        let head = text.components(
            separatedBy: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "(;{="))
        ).first ?? text
        return head.contains("::") && head.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func isConstructorDeclaration(_ text: String) -> Bool {
        guard let openParen = text.firstIndex(of: "(") else { return false }
        guard !text.hasSuffix(".") && !text.hasSuffix("?") && !text.hasSuffix("!") else { return false }

        let beforeParen = text[..<openParen].trimmingCharacters(in: .whitespaces)
        guard !beforeParen.isEmpty else { return false }

        var baseName = beforeParen
        if let genericStart = beforeParen.firstIndex(of: "<") {
            baseName = String(beforeParen[..<genericStart]).trimmingCharacters(in: .whitespaces)
        }

        let stopwords: Set<String> = [
            "note", "warning", "important", "see", "if", "when", "for", "while",
            "in", "this", "the", "returns", "return", "throws", "throw",
            "parameter", "parameters", "example", "details", "arguments", "args"
        ]
        if stopwords.contains(baseName.lowercased()) {
            return false
        }

        guard LSPHoverSectionExtractor.isValidIdentifier(baseName) else { return false }

        // If there is text following the closing parenthesis, verify it looks like declaration syntax
        if let closeParen = text.lastIndex(of: ")") {
            let afterParen = text[closeParen...].dropFirst().trimmingCharacters(in: .whitespaces)
            if !afterParen.isEmpty {
                let validTrailingStarters = [":", ";", "{", "=", "noexcept", "const", "override", "explicit", "final"]
                let hasValidTrailing = validTrailingStarters.contains { afterParen.hasPrefix($0) }
                if !hasValidTrailing {
                    return false
                }
            }
        }

        return true
    }

    private static func isSignatureComplete(_ code: String) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        // An attribute alone (e.g. `@MainActor` or `[[nodiscard]]`) is not a complete signature
        if isAttributeStarter(trimmed) && !trimmed.contains("\n") {
            return false
        }

        // A template header alone (e.g. `template <typename T>`) is not a complete signature
        if isTemplateHeaderOnly(trimmed) {
            return false
        }

        if hasContinuationEnding(trimmed) {
            return false
        }
        return areDelimitersBalanced(trimmed)
    }

    private static func isTemplateHeaderOnly(_ code: String) -> Bool {
        guard code.hasPrefix("template") else { return false }
        guard let closeGeneric = code.lastIndex(of: ">") else { return true }
        let afterClose = code[closeGeneric...].dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        return afterClose.isEmpty
    }

    private static func hasContinuationEnding(_ text: String) -> Bool {
        let continuationEndings = [",", "(", "[", "{", "->", "=>", ":", "where", "\\"]
        return continuationEndings.contains(where: { text.hasSuffix($0) })
    }

    private static func areDelimitersBalanced(_ text: String) -> Bool {
        var counts: [Character: Int] = ["(": 0, "[": 0, "<": 0]
        let matching: [Character: Character] = [")": "(", "]": "[", ">": "<"]
        var inQuote: Character?

        for char in text {
            if let quote = inQuote {
                if char == quote { inQuote = nil }
                continue
            }
            if char == "\"" {
                inQuote = char
                continue
            }
            if let open = matching[char] {
                if let depth = counts[open], depth > 0 { counts[open] = depth - 1 }
            } else if counts[char] != nil {
                counts[char, default: 0] += 1
            }
        }

        return counts.values.allSatisfy { $0 == 0 } && inQuote == nil
    }

}

// MARK: - Divider Handling

extension LSPHoverParser {
    /// Normalizes divider markers (em-dashes `———`, markdown rules `---`, etc.) into line-separated dividers.
    static func normalizeDividers(_ text: String) -> String {
        var result = text

        // 1. Replace runs of 2+ em-dashes, en-dashes, horizontal bars, or fullwidth hyphens
        let dashPatterns = "[—―⸺⸻－–]{2,}"
        result = result.replacingOccurrences(of: dashPatterns, with: "\n---\n", options: .regularExpression)

        // 2. Replace runs of 3+ hyphens, asterisks, or underscores (e.g. "---", "***", "___")
        let multiHyphenOrAsterisk = "(?:[ \\t]*[-]{3,}[ \\t]*|[ \\t]*[*]{3,}[ \\t]*|[ \\t]*[_]{3,}[ \\t]*)"
        result = result.replacingOccurrences(of: multiHyphenOrAsterisk, with: "\n---\n", options: .regularExpression)

        // 3. Replace double hyphen with spaces (e.g. "core -- // In namespace")
        let doubleHyphenWithSpaces = "[ \\t]+--[ \\t]+"
        result = result.replacingOccurrences(of: doubleHyphenWithSpaces, with: "\n---\n", options: .regularExpression)

        // 4. Replace inline em-dash / en-dash between code/tokens and comments or next text
        let inlineEmDashWithComment = "([a-zA-Z0-9_>)}\\]])[ \\t]*[—―⸺⸻－–]+[ \\t]*(?=//|[a-zA-Z0-9_#])"
        result = result.replacingOccurrences(
            of: inlineEmDashWithComment,
            with: "$1\n---\n",
            options: .regularExpression
        )

        // 5. Replace single em-dash / en-dash surrounded by spaces
        let singleDashSurrounded = "[ \\t]+[—―⸺⸻－–][ \\t]+"
        result = result.replacingOccurrences(of: singleDashSurrounded, with: "\n---\n", options: .regularExpression)

        return result
    }

    /// Determines whether a line represents a divider (e.g. `---`, `***`, `___`, `———`).
    static func isDividerLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        let nonSpace = trimmed.filter { !$0.isWhitespace }
        guard !nonSpace.isEmpty else { return false }

        if nonSpace.allSatisfy({ $0 == "-" }) && nonSpace.count >= 3 { return true }
        if nonSpace.allSatisfy({ $0 == "*" }) && nonSpace.count >= 3 { return true }
        if nonSpace.allSatisfy({ $0 == "_" }) && nonSpace.count >= 3 { return true }

        let emDashes: Set<Character> = ["\u{2014}", "\u{2015}", "\u{2E3A}", "\u{2E3B}", "\u{FF0D}"]
        if nonSpace.allSatisfy({ emDashes.contains($0) }) { return true }

        if nonSpace.allSatisfy({ $0 == "\u{2013}" }) && nonSpace.count >= 2 { return true }

        return false
    }

    /// Strips leading divider markers like `---`, `***`, `___`, or `———`.
    static func stripLeadingDividers(_ text: inout String) {
        var lines = text.components(separatedBy: "\n")
        while let first = lines.first, isDividerLine(first) || first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
