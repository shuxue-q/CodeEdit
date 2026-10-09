//
//  FunctionCallInsertion.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// Decides what accepting a function completion appends after the function's name.
///
/// Pure: it looks only at the item's label and detail and at the character that follows the
/// completed word, so it can be tested without an editor.
enum FunctionCallInsertion {
    /// The text to append to the completed name and where the caret goes.
    struct Insertion: Equatable {
        /// The text to append after the name, always `()`.
        let text: String
        /// The caret's UTF-16 offset within ``text``: `1` between the parentheses, `2` after them.
        let caretOffset: Int
    }

    /// The parentheses to insert for a function named by `label`, or `nil` when none should be added.
    ///
    /// - Parameters:
    ///   - label: The item's label. Servers differ in whether it carries the signature
    ///     (`foo(int a)`) or only the name.
    ///   - detail: The item's detail, consulted for a signature when the label has none.
    ///   - nextCharacter: The character right after the completed word, if any. An existing `(`
    ///     means the call is already written.
    ///   - commitCharacter: The character the user typed to accept the item, if any. `(`, `)` and `[`
    ///     are part of the call syntax themselves, so nothing is inserted; for `.`, `,` and `;` the
    ///     caret ends up after the parentheses so typing continues from there.
    /// - Returns: The caret goes between the parentheses when the signature has parameters or cannot
    ///   be determined, and after them when the function takes none.
    static func insertion(
        label: String,
        detail: String?,
        nextCharacter: Character?,
        commitCharacter: Character? = nil
    ) -> Insertion? {
        guard nextCharacter != "(" else { return nil }
        let name = label.drop { $0 == "•" || $0 == " " }
        // `operator()` and friends already name their own parentheses.
        guard !name.hasPrefix("operator") else { return nil }
        if let commitCharacter {
            return CommitCharacters.suppressesCallParentheses.contains(commitCharacter)
                ? nil
                : Insertion(text: "()", caretOffset: 2)
        }

        let hasParameters = parameters(in: String(name)) ?? detail.flatMap(parameters(in:))
        if hasParameters == false {
            return Insertion(text: "()", caretOffset: 2)
        }
        return Insertion(text: "()", caretOffset: 1)
    }

    /// Whether the first parenthesized group in `signature` lists parameters, or `nil` when `signature`
    /// has no balanced parentheses to read.
    static func parameters(in signature: String) -> Bool? {
        guard let open = signature.firstIndex(of: "(") else { return nil }
        var depth = 0
        var index = open
        while index < signature.endIndex {
            switch signature[index] {
            case "(":
                depth += 1
            case ")":
                depth -= 1
                if depth == 0 {
                    let inside = signature[signature.index(after: open)..<index]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return !(inside.isEmpty || inside == "void")
                }
            default:
                break
            }
            index = signature.index(after: index)
        }
        return nil
    }
}
