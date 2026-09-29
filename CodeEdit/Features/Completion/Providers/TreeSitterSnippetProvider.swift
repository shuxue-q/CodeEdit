//
//  TreeSitterSnippetProvider.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol

/// Supplies context-gated code snippets and plain keywords from static per-language tables.
///
/// The first pass covers C and C++. The table structure allows more languages to be added later.
final class TreeSitterSnippetProvider: CompletionProvider {
    /// One snippet table entry.
    struct Snippet {
        let label: String
        /// LSP snippet syntax: `${1:cond}`, `$0`.
        let body: String
        let detail: String
        let allowedContexts: Set<SyntacticContext>
    }

    let source: CompletionSource = .snippet
    let deadline: Duration = .zero

    func triggerCharacters() -> Set<String> { [] }

    func candidates(for context: CompletionContext, textView: TextViewController) async -> [CompletionCandidate] {
        let snippets = Self.snippets[context.languageId] ?? []
        let keywords = Self.keywords[context.languageId] ?? []

        var candidates: [CompletionCandidate] = []
        for snippet in snippets where snippet.allowedContexts.contains(context.syntax) {
            candidates.append(
                CompletionCandidate(
                    id: "snippet.\(context.languageId).\(snippet.label)",
                    label: snippet.label,
                    filterText: snippet.label,
                    sortText: snippet.label,
                    kind: .snippet,
                    source: .snippet,
                    detail: snippet.detail,
                    documentation: nil,
                    payload: .snippet(body: snippet.body)
                )
            )
        }
        for keyword in keywords {
            candidates.append(
                CompletionCandidate(
                    id: "keyword.\(context.languageId).\(keyword)",
                    label: keyword,
                    filterText: keyword,
                    sortText: keyword,
                    kind: .keyword,
                    source: .keyword,
                    detail: nil,
                    documentation: nil,
                    payload: .plain(insertText: keyword)
                )
            )
        }
        return candidates
    }

    func apply(_ candidate: CompletionCandidate, textView: TextViewController, cursorPosition: CursorPosition?) {
        guard let cursorPosition, let resolved = textView.resolveCursorPosition(cursorPosition) else { return }
        let location = resolved.range.location
        let string = textView.textView.textStorage.string as NSString
        var wordStart = location
        while wordStart > 0,
              let scalar = Unicode.Scalar(string.character(at: wordStart - 1)),
              Self.wordCharacters.contains(scalar) {
            wordStart -= 1
        }
        let replaceRange = NSRange(location: wordStart, length: location - wordStart)

        switch candidate.payload {
        case .snippet(let body):
            textView.insertSnippet(body, replacing: replaceRange)
        case .plain(let text):
            textView.textView.replaceCharacters(in: replaceRange, with: text)
        case .lsp:
            return
        }
    }

    private static let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$#"))

    // MARK: - Tables

    private static let cKeywords = [
        "for", "while", "if", "else", "return", "struct", "const", "static", "switch", "break",
        "continue", "sizeof", "typedef", "void", "int", "char", "float", "double"
    ]
    private static let cppKeywords = cKeywords + [
        "class", "namespace", "template", "public", "private", "protected", "virtual", "override",
        "new", "delete", "nullptr", "auto", "constexpr"
    ]

    private static let cSnippets: [Snippet] = [
        Snippet(
            label: "for",
            body: "for (${1:int i = 0}; ${2:i < n}; ${3:++i}) {\n\t$0\n}",
            detail: "for (init; cond; inc) {…}",
            allowedContexts: [.statement, .unknown]
        ),
        Snippet(
            label: "while",
            body: "while (${1:cond}) {\n\t$0\n}",
            detail: "while (cond) {…}",
            allowedContexts: [.statement, .unknown]
        ),
        Snippet(
            label: "if",
            body: "if (${1:cond}) {\n\t$0\n}",
            detail: "if (cond) {…}",
            allowedContexts: [.statement, .unknown]
        ),
        Snippet(
            label: "struct",
            body: "struct ${1:Name} {\n\t$0\n};",
            detail: "struct Name {…};",
            allowedContexts: [.topLevel, .unknown]
        ),
        Snippet(
            label: "#include <insert>",
            body: "include <$0>",
            detail: "Include system header",
            allowedContexts: [.preprocessor]
        )
    ]

    private static let cppSnippets: [Snippet] = cSnippets + [
        Snippet(
            label: "class",
            body: "class ${1:Name} {\npublic:\n\t$0\n};",
            detail: "class Name {…};",
            allowedContexts: [.topLevel, .unknown]
        )
    ]

    private static let keywords: [String: [String]] = [
        "c": cKeywords,
        "cpp": cppKeywords
    ]

    private static let snippets: [String: [Snippet]] = [
        "c": cSnippets,
        "cpp": cppSnippets
    ]
}
