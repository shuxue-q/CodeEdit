//
//  LSPHoverSectionExtractor+Symbol.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/17/26.
//

import Foundation

// MARK: - Symbol Extraction

extension LSPHoverSectionExtractor {
    /// Attempts to extract the symbol name from a declaration string.
    static func extractSymbolName(from code: String) -> String? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cleaned = cleanDeclarationPrefixes(trimmed)

        if let typedefSymbol = extractTypedefSymbol(from: cleaned) { return typedefSymbol }
        if let special = extractSpecialSymbol(from: cleaned) { return special }
        if let funcSymbol = extractFunctionSymbol(from: cleaned) { return funcSymbol }
        if let qualifiedSymbol = extractQualifiedSymbol(from: cleaned) { return qualifiedSymbol }
        if let wordSymbol = extractWordSymbol(from: cleaned) { return wordSymbol }
        return extractColonSymbol(from: cleaned)
    }

    private static func extractWordSymbol(from cleaned: String) -> String? {
        let stripped = stripLeadingModifiers(cleaned)
        let delimiterChars = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":<{=;"))
        let words = stripped.components(separatedBy: delimiterChars).filter { !$0.isEmpty }

        if let typeSymbol = extractTypeSymbol(words: words) { return typeSymbol }
        if let varSymbol = extractVariableSymbol(words: words) { return varSymbol }
        if let typedVarSymbol = extractTypedVariableSymbol(words: words) { return typedVarSymbol }
        return nil
    }

    private static func extractColonSymbol(from cleaned: String) -> String? {
        guard !cleaned.contains("::"), let colonIdx = cleaned.firstIndex(of: ":") else { return nil }
        if cleaned.contains("(") && cleaned.firstIndex(of: "(")! <= colonIdx { return nil }

        let beforeColon = String(cleaned[..<colonIdx]).trimmingCharacters(in: .whitespaces)
        let tokens = beforeColon.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard let lastToken = tokens.last else { return nil }
        let cand = cleanIdentifier(lastToken)
        return (isValidIdentifier(cand) && !isLanguageKeyword(cand) && !isModifier(cand)) ? cand : nil
    }

    private static func cleanDeclarationPrefixes(_ code: String) -> String {
        var cleaned = code
        let prefixes = [
            "(function) ", "(method) ", "(class) ", "(variable) ", "(property) ",
            "(type) ", "(constant) ", "(alias) ", "(interface) ", "(enum) "
        ]
        while let matched = prefixes.first(where: { cleaned.hasPrefix($0) }) {
            cleaned = String(cleaned.dropFirst(matched.count))
        }
        return cleaned
    }

    private static func extractTypedefSymbol(from cleaned: String) -> String? {
        guard cleaned.hasPrefix("typedef ") else { return nil }
        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "; \t\n"))
        if let openParen = trimmed.firstIndex(of: "("),
           let closeParen = trimmed.firstIndex(of: ")"), openParen < closeParen {
            let inside = trimmed[trimmed.index(after: openParen)..<closeParen]
            let insideClean = inside.trimmingCharacters(in: CharacterSet(charactersIn: "* \t"))
            if isValidIdentifier(insideClean) && !isLanguageKeyword(insideClean) {
                return insideClean
            }
        }
        let tokens = trimmed.components(
            separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ";="))
        ).filter { !$0.isEmpty }
        guard let last = tokens.last else { return nil }
        let candidate = cleanIdentifier(last)
        return (isValidIdentifier(candidate) && !isLanguageKeyword(candidate)) ? candidate : nil
    }

    private static func stripLeadingModifiers(_ text: String) -> String {
        var working = text
        let prefixes = [
            "static ", "extern ", "inline ", "constexpr ", "consteval ", "constinit ", "const ",
            "volatile ", "mutable ", "pub ", "public ", "private ", "internal ", "open ", "final ",
            "lazy ", "thread_local "
        ]
        while let matched = prefixes.first(where: { working.hasPrefix($0) }) {
            working = String(working.dropFirst(matched.count)).trimmingCharacters(in: .whitespaces)
        }
        return working
    }

    private static func extractSpecialSymbol(from cleaned: String) -> String? {
        if cleaned.contains("init(") || cleaned.contains("init<") || cleaned.contains("init?(") { return "init" }
        if cleaned.contains("subscript(") || cleaned.contains("subscript<") { return "subscript" }
        return nil
    }

    private static func extractQualifiedSymbol(from cleaned: String) -> String? {
        guard cleaned.contains("::") else { return nil }
        let parts = cleaned.components(
            separatedBy: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "(;{="))
        )
        guard let firstToken = parts.first, firstToken.contains("::") else { return nil }
        let segments = firstToken.components(separatedBy: "::")
        guard let last = segments.last else { return nil }
        let cleanedLast = cleanIdentifier(last)
        return (isValidIdentifier(cleanedLast) && !isLanguageKeyword(cleanedLast)) ? cleanedLast : nil
    }

    private static func extractFunctionSymbol(from cleaned: String) -> String? {
        guard let openParenIdx = cleaned.firstIndex(of: "(") else { return nil }
        let beforeParen = String(cleaned[..<openParenIdx]).trimmingCharacters(in: .whitespaces)

        var nameCandidate = beforeParen
        if beforeParen.hasSuffix(">"), let matchingOpen = findMatchingGenericOpen(in: beforeParen) {
            nameCandidate = String(beforeParen[..<matchingOpen]).trimmingCharacters(in: .whitespaces)
        }
        if nameCandidate.contains(")") {
            if let lastClose = nameCandidate.lastIndex(of: ")") {
                nameCandidate = String(nameCandidate[lastClose...].dropFirst()).trimmingCharacters(in: .whitespaces)
            }
        }

        if let operatorRange = nameCandidate.range(of: "operator") {
            return String(nameCandidate[operatorRange.lowerBound...]).trimmingCharacters(in: .whitespaces)
        }

        let splitChars = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "*&"))
        let tokens = nameCandidate.components(separatedBy: splitChars).filter { !$0.isEmpty }
        guard let lastToken = tokens.last else { return nil }
        var cleanedToken = cleanIdentifier(lastToken)

        if cleanedToken.contains("::") {
            let parts = cleanedToken.components(separatedBy: "::")
            if let lastPart = parts.last {
                cleanedToken = cleanIdentifier(lastPart)
            }
        }

        return (isValidIdentifier(cleanedToken) && !isLanguageKeyword(cleanedToken)) ? cleanedToken : nil
    }

    private static func findMatchingGenericOpen(in text: String) -> String.Index? {
        guard text.hasSuffix(">") else { return nil }
        var depth = 0
        for idx in text.indices.reversed() {
            let char = text[idx]
            if char == ">" {
                depth += 1
            } else if char == "<" {
                depth -= 1
                if depth == 0 { return idx }
            }
        }
        return nil
    }
}

// MARK: - Symbol Extraction Word Helpers

extension LSPHoverSectionExtractor {
    private static func extractTypeSymbol(words: [String]) -> String? {
        let typeDeclarators: Set<String> = [
            "class", "struct", "enum", "protocol", "actor", "typealias", "trait", "interface",
            "namespace", "union", "concept", "using"
        ]
        for (idx, word) in words.enumerated() where typeDeclarators.contains(word) {
            for nextIdx in (idx + 1)..<words.count {
                let candidate = cleanIdentifier(words[nextIdx])
                if isValidIdentifier(candidate) && !isModifier(candidate)
                    && !isLanguageKeyword(candidate) && !isTypeKeyword(candidate) {
                    return candidate
                }
            }
        }
        return nil
    }

    private static func extractVariableSymbol(words: [String]) -> String? {
        let varDeclarators: Set<String> = ["var", "let", "const", "val", "mut"]
        for (idx, word) in words.enumerated() where varDeclarators.contains(word) {
            for nextIdx in (idx + 1)..<words.count {
                let candidate = cleanIdentifier(words[nextIdx])
                let isUsable = isValidIdentifier(candidate) && !isModifier(candidate)
                    && !isTypeKeyword(candidate) && !isLanguageKeyword(candidate)
                if isUsable { return candidate }
            }
        }
        return nil
    }

    private static func extractTypedVariableSymbol(words: [String]) -> String? {
        guard words.count >= 2 else { return nil }
        let firstToken = words.first!
        let candidate = cleanIdentifier(words[1])
        guard isValidIdentifier(candidate) && !isLanguageKeyword(candidate) && !isModifier(candidate) else {
            return nil
        }
        if isTypeKeyword(firstToken) || firstToken.first?.isUppercase == true || firstToken.contains("::") {
            return candidate
        }
        return nil
    }

    private static func isModifier(_ word: String) -> Bool {
        let modifiers: Set<String> = [
            "public", "private", "fileprivate", "internal", "open", "static", "final", "mutating",
            "nonmutating", "override", "required", "convenience", "weak", "unowned", "lazy", "pub",
            "async", "constexpr", "consteval", "constinit", "inline", "virtual", "extern", "explicit",
            "friend", "mutable", "volatile"
        ]
        return modifiers.contains(word)
    }

    private static func isLanguageKeyword(_ word: String) -> Bool {
        let keywords: Set<String> = [
            "func", "def", "fn", "function", "var", "let", "const", "val", "class", "struct", "enum",
            "protocol", "actor", "typealias", "type", "return", "throws", "rethrows", "async", "await",
            "where", "import", "as", "is", "namespace", "template", "using", "typedef", "concept", "union", "auto"
        ]
        return keywords.contains(word)
    }

    private static func isTypeKeyword(_ word: String) -> Bool {
        let types: Set<String> = [
            "int", "char", "short", "long", "float", "double", "void", "bool", "size_t",
            "int32_t", "uint32_t", "int64_t", "uint64_t", "auto"
        ]
        return types.contains(word.lowercased())
    }
}
