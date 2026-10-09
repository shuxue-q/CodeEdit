//
//  CommitCharacters.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// The characters that accept a completion item when they are typed while it is highlighted.
enum CommitCharacters {
    /// The default for C-family languages. `>` completes only after `->`, where nothing has been
    /// typed yet, so the window's non-empty-prefix rule leaves it inert; it is listed for completeness.
    static let cFamily: Set<Character> = ["(", ".", ";", ",", ")", "[", ">"]

    /// Language identifiers that use ``cFamily``.
    private static let cFamilyLanguages: Set<String> = ["c", "cpp", "objc", "objcpp", "cuda"]

    /// Characters after which a function's own parentheses must not be inserted, because the
    /// character typed next is, or closes, the call.
    static let suppressesCallParentheses: Set<Character> = ["(", ")", "["]

    /// The commit characters for `candidate`, given what has been typed.
    ///
    /// A language-server item's own `commitCharacters` win. Otherwise C-family documents use
    /// ``cFamily`` and other languages commit nothing. Only language-server items commit: snippets,
    /// keywords, AI suggestions, document words, and file paths never do, because a character typed
    /// after them is far more likely to be text.
    ///
    /// Nothing commits when `prefix` is empty, or when `prefix` names a different candidate in
    /// `pool`: typing `i.` or `x(` means that variable, not the row that merely sorts first for it.
    static func characters(
        for candidate: CompletionCandidate,
        languageId: String,
        prefix: String,
        pool: [CompletionCandidate]
    ) -> Set<Character> {
        guard candidate.source == .lsp, !prefix.isEmpty else { return [] }
        if candidate.kind == .file || candidate.kind == .folder || candidate.kind == .snippet {
            return []
        }
        let selectedName = name(of: candidate.label)
        let typedNamesAnotherCandidate = pool.contains {
            let other = name(of: $0.label)
            return other == prefix && other != selectedName
        }
        guard !typedNamesAnotherCandidate else { return [] }

        if case .lsp(let item) = candidate.payload,
           let fromServer = item.commitCharacters, !fromServer.isEmpty {
            return Set(fromServer.compactMap(\.first))
        }
        return cFamilyLanguages.contains(languageId) ? cFamily : []
    }

    /// The bare symbol name in a row label: without padding, the include marker, a signature, or
    /// template arguments.
    static func name(of label: String) -> String {
        let normalized = CompletionDeduplicator.normalizedLabel(label)
        let end = normalized.firstIndex { $0 == "(" || $0 == "<" } ?? normalized.endIndex
        return String(normalized[..<end])
    }
}
