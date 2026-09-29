//
//  SnippetText.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import Foundation
import LanguageServerProtocol

/// Shared helpers for parsing LSP snippet syntax (`${1:placeholder}`, `$0`) into plain text.
///
/// Moved out of the LSP completion delegate so both ``LSPCompletionProvider`` and
/// ``TreeSitterSnippetProvider`` can apply snippet bodies the same way.
enum SnippetText {
    /// Parses snippet syntax to plain text and returns the offset of the first tab stop (`$0` or `$1`).
    static func parseSnippet(
        text: String,
        format: InsertTextFormat?
    ) -> (stripped: String, cursorOffset: Int?) {
        guard format == .snippet else { return (text, nil) }

        var cursorOffset: Int?
        if let tabStopRange = text.range(of: #"\$(?:0|\{0\}|1|\{1(?::[^}]*)?\})"#, options: .regularExpression) {
            let prefix = String(text[..<tabStopRange.lowerBound])
            let cleanPrefix = stripSnippetSyntax(from: prefix, format: .snippet)
            cursorOffset = (cleanPrefix as NSString).length
        }

        let stripped = stripSnippetSyntax(from: text, format: .snippet)
        return (stripped, cursorOffset)
    }

    /// Converts snippet syntax into plain text, replacing `${n:placeholder}` with the placeholder
    /// and removing `$n` / `${n}` tab stops.
    static func stripSnippetSyntax(from text: String, format: InsertTextFormat?) -> String {
        guard format == .snippet else { return text }
        var result = text
        // swiftlint:disable force_try
        let placeholderPattern = try! NSRegularExpression(pattern: #"\$\{\d+:([^}]*)\}"#)
        let tabStopPattern = try! NSRegularExpression(pattern: #"\$\{\d+\}|\$\d+"#)
        // swiftlint:enable force_try
        result = placeholderPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "$1"
        )
        result = tabStopPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: ""
        )
        return result
    }
}
