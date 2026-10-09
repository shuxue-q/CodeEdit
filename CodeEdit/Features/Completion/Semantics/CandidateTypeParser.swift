//
//  CandidateTypeParser.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// Reads the type a completion candidate evaluates to out of the text the language server attaches.
///
/// clangd puts a function's return type, and a variable's, field's or enumerator's type, in the item's
/// `detail`. Types, namespaces and headers evaluate to no value and have no result type, so they never
/// receive an expected-type bonus.
enum CandidateTypeParser {
    /// The kinds of language server item whose `detail` is the type of the value they stand for.
    private static let valueKinds: Set<LSPCompletionCategory> = [
        .function, .variable, .enumMember, .macro, .keyword, .snippet
    ]

    /// The longest `detail` taken for a type; longer text is a signature or documentation.
    private static let maximumDetailLength = 120

    /// The type of the value `candidate` stands for, or `nil` for types, namespaces, headers, items
    /// from other sources, and items whose `detail` is not a type.
    static func resultType(of candidate: CompletionCandidate) -> TypeText? {
        guard candidate.source == .lsp,
              valueKinds.contains(candidate.kind),
              !candidate.label.hasPrefix("#"),
              let detail = candidate.detail else {
            return nil
        }
        let firstLine = detail.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first
        guard let text = firstLine?.trimmingCharacters(in: .whitespaces),
              !text.isEmpty,
              text.count <= maximumDetailLength,
              looksLikeType(text) else {
            return nil
        }
        return TypeText.parse(text)
    }

    /// Whether `text` has the shape of a C++ type rather than prose such as "Include system header".
    private static func looksLikeType(_ text: String) -> Bool {
        text.range(of: #"^[A-Za-z_:][A-Za-z0-9_:<>,\s\*&\(\)\[\]]*$"#, options: .regularExpression) != nil
            && !text.contains("include")
            && text.range(of: #"^[A-Za-z_:][\w:]*(\s+[A-Za-z_][\w:]*){3,}$"#, options: .regularExpression) == nil
    }
}
