//
//  SuggestionCompletionInfo.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit Contributors on 9/27/26.
//

import Foundation

/// Text shown in the documentation panel for one completion.
enum SuggestionPreviewContent {
    /// Detail and documentation for the selected item.
    ///
    /// A signature in `detail` is kept even when every item's documentation is the same header line.
    static func text(for item: CodeSuggestionEntry) -> String? {
        let detail = trimmed(item.detail)
        let documentation = trimmed(item.documentation)
        switch (detail, documentation) {
        case (nil, nil):
            return nil
        case let (detail?, nil):
            return detail
        case let (nil, documentation?):
            return documentation
        case let (detail?, documentation?):
            if documentation.contains(detail) {
                return documentation
            }
            return detail + "\n\n" + documentation
        }
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Header named by a completion, such as `<type_traits>`.
enum SuggestionOrigin {
    /// Reads a `From \`<header>\`` line out of completion documentation.
    static func header(in documentation: String?) -> String? {
        guard let documentation else { return nil }
        let patterns = [
            #"From\s+`([^`]+)`"#,
            #"From\s+(<[^>\n]+>)"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(documentation.startIndex..., in: documentation)
            guard let match = expression.firstMatch(in: documentation, range: range),
                  match.numberOfRanges > 1,
                  let headerRange = Range(match.range(at: 1), in: documentation) else {
                continue
            }
            let header = String(documentation[headerRange])
            if !header.isEmpty {
                return header
            }
        }
        return nil
    }
}
