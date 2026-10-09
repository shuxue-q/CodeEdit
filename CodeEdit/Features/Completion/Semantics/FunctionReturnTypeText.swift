//
//  FunctionReturnTypeText.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// Reads a function's return type from the start of its declaration.
enum FunctionReturnTypeText {
    /// Words that precede the return type without being part of it.
    private static let specifiers: Set<String> = [
        "static", "inline", "virtual", "constexpr", "consteval", "extern", "explicit", "friend"
    ]

    /// The characters a return type is written with.
    private static let typeCharacters: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "_:<>,*& ")
        return set
    }()

    /// The return type in `declaration`, the text from the start of a declaration up to the function's name
    /// (`static std::string *`), or `nil` when it names no concrete type: a constructor, `void`, `auto`, or
    /// text that is not a type.
    ///
    /// Pointer stars are kept and references dropped, like the syntax-tree path of ``ExpectedTypeResolver``.
    static func parse(_ declaration: String) -> TypeText? {
        var text = declaration
        while let template = text.range(of: "template"), template.lowerBound == text.startIndex {
            let rest = text[template.upperBound...].drop { $0.isWhitespace }
            guard rest.first == "<" else { break }
            var depth = 0
            var end = rest.startIndex
            for index in rest.indices {
                if rest[index] == "<" { depth += 1 } else if rest[index] == ">" { depth -= 1 }
                if depth == 0 {
                    end = rest.index(after: index)
                    break
                }
            }
            guard depth == 0 else { return nil }
            text = String(rest[end...]).trimmingCharacters(in: .whitespaces)
        }
        while let open = text.range(of: "[[") {
            guard let close = text.range(of: "]]", range: open.upperBound..<text.endIndex) else { return nil }
            text.removeSubrange(open.lowerBound..<close.upperBound)
        }
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
            .filter { !specifiers.contains($0) }
        let remaining = words.joined(separator: " ")
        guard !remaining.isEmpty, remaining.unicodeScalars.allSatisfy({ typeCharacters.contains($0) }),
              let type = TypeText.parse(remaining), !(type.name == "void" && type.pointerDepth == 0) else {
            return nil
        }
        return type
    }
}
