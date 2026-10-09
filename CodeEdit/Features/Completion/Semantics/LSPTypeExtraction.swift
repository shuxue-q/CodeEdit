//
//  LSPTypeExtraction.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation
import LanguageServerProtocol

/// Pulls types out of language server hover and signature help answers.
enum LSPTypeExtraction {
    // MARK: - Hover

    /// The text of a hover answer, whatever markup the server used.
    static func text(of hover: Hover) -> String {
        switch hover.contents {
        case .optionA(let markedString):
            return text(of: markedString)
        case .optionB(let markedStrings):
            return markedStrings.map(text(of:)).joined(separator: "\n\n")
        case .optionC(let markup):
            return markup.value
        }
    }

    private static func text(of markedString: MarkedString) -> String {
        switch markedString {
        case .optionA(let string): return string
        case .optionB(let pair): return pair.value
        }
    }

    /// The type a hover over a variable, field or function names: clangd writes `Type: std::vector<int>`
    /// for values and `→ int` or `Returns: int` for functions. Backticks around the type are ignored.
    static func type(fromHover text: String) -> TypeText? {
        let patterns = [
            #"(?m)^[\s\-\*]*Type:\s*`?([^`\n]+?)`?\s*$"#,
            #"(?m)^[\s\-\*]*(?:→|->|Returns:)\s*`?([^`\n]+?)`?\s*$"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text),
                  let parsed = TypeText.parse(String(text[range])) else {
                continue
            }
            return parsed
        }
        return nil
    }

    // MARK: - Signature help

    /// The type of the parameter the cursor is at, from the active signature of `help`.
    static func activeParameterType(in help: SignatureHelp) -> TypeText? {
        guard !help.signatures.isEmpty else { return nil }
        let index = min(max(help.activeSignature ?? 0, 0), help.signatures.count - 1)
        let signature = help.signatures[index]
        let parameters = signature.parameters ?? []
        let activeIndex = signature.activeParameter.map { Int($0) } ?? help.activeParameter ?? 0
        guard parameters.indices.contains(activeIndex) else { return nil }
        let ranges = LSPSignatureHelpContent.parameterRanges(parameters.map(\.label), in: signature.label)
        guard let range = ranges[activeIndex] else { return nil }
        let label = (signature.label as NSString).substring(with: range)
        return parameterType(fromLabel: label)
    }

    /// The type in a parameter label such as `const std::string &name` or `int = 0`.
    static func parameterType(fromLabel label: String) -> TypeText? {
        var text = label
        if let equals = text.firstIndex(of: "=") {
            text = String(text[..<equals])
        }
        text = text.trimmingCharacters(in: .whitespaces)
        // A trailing identifier after a type, a space, `&`, `*` or `>` is the parameter's name.
        if let regex = try? NSRegularExpression(pattern: #"(?<![:\w])[A-Za-z_]\w*$"#),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let nameRange = Range(match.range, in: text) {
            let typePart = String(text[..<nameRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            if hasTypeBeyondQualifiers(typePart), !endsWithPrimitiveWord(text) {
                text = typePart
            }
        }
        return TypeText.parse(text)
    }

    private static let qualifierWords: Set<String> = ["const", "volatile", "struct", "class", "enum", "typename"]
    private static let primitiveWords: Set<String> = [
        "int", "char", "short", "long", "double", "float", "bool", "void", "unsigned", "signed", "wchar_t"
    ]

    /// Whether `text` holds a type name and not just qualifiers such as `const`.
    private static func hasTypeBeyondQualifiers(_ text: String) -> Bool {
        let words = text.split { !($0.isLetter || $0.isNumber || $0 == "_" || $0 == ":") }.map(String.init)
        return words.contains { !qualifierWords.contains($0) }
    }

    /// Whether the last word is a primitive type word (`unsigned int`), which is part of the type.
    private static func endsWithPrimitiveWord(_ text: String) -> Bool {
        guard let last = text.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") }).last else {
            return false
        }
        return primitiveWords.contains(String(last))
    }
}
