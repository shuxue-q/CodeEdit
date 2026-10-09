//
//  ReceiverTypeResolver.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// Finds the type of the object whose members are being completed (`v` in `v.|`, `node->|`,
/// `make().|`), so acceptances can be remembered per receiver type.
///
/// The receiver's name is found in the text before the typed prefix and its type is read from the
/// language server's hover on that name. For a call, the hover is on the called function and gives its
/// return type. Pointers are ignored: `Point *p` and `Point p` both give `Point`, because the members
/// are those of the pointee. Anything this cannot tell (a subscript, a literal, a parenthesized
/// expression, a hover that fails or is late) gives `nil`, and the ranker falls back to per-intent
/// statistics.
struct ReceiverTypeResolver {
    /// The type of the symbol that starts at an offset, from the language server's hover.
    let typeOfSymbol: (_ offset: Int) async -> TypeText?

    /// The normalized name of the receiver's type, for example `std::vector<int>`.
    /// - Parameters:
    ///   - text: The document.
    ///   - prefixStart: The offset where the typed prefix starts, right after the `.` or `->`.
    ///   - intent: Only member access has a receiver.
    ///   - languageId: Only the C family is resolved.
    func resolve(text: String, prefixStart: Int, intent: CompletionIntent, languageId: String) async -> String? {
        guard intent == .memberAccess, CFamilyKeywords.languageIds.contains(languageId) else { return nil }
        let string = text as NSString
        guard prefixStart >= 2, prefixStart <= string.length,
              let symbol = receiverSymbolOffset(in: string, operatorEnd: prefixStart) else {
            return nil
        }
        return await typeOfSymbol(symbol)?.name
    }

    /// The offset of the name that gives the receiver's type, for the `.` or `->` that ends at `operatorEnd`.
    private func receiverSymbolOffset(in string: NSString, operatorEnd: Int) -> Int? {
        var end = operatorEnd - 1
        if string.character(at: end) == 0x2E {
            // `.`
        } else if string.character(at: end) == 0x3E, end > 0, string.character(at: end - 1) == 0x2D {
            end -= 1
        } else {
            return nil
        }
        guard end > 0 else { return nil }
        if string.character(at: end - 1) == 0x29 {
            guard let open = matchingOpenParenthesis(forCloseAt: end - 1, in: string) else { return nil }
            end = open
        }
        let start = identifierStart(endingAt: end, in: string)
        return start < end ? start : nil
    }

    private func identifierStart(endingAt end: Int, in string: NSString) -> Int {
        var start = end
        while start > 0, Self.isIdentifierCharacter(string.character(at: start - 1)) { start -= 1 }
        return start
    }

    private func matchingOpenParenthesis(forCloseAt close: Int, in string: NSString) -> Int? {
        var depth = 0
        var index = close
        while index >= 0 {
            switch string.character(at: index) {
            case 0x29: depth += 1
            case 0x28:
                depth -= 1
                if depth == 0 { return index }
            default: break
            }
            index -= 1
        }
        return nil
    }

    private static func isIdentifierCharacter(_ unit: unichar) -> Bool {
        Unicode.Scalar(unit).map { CharacterSet.alphanumerics.contains($0) || $0 == "_" } ?? false
    }
}
