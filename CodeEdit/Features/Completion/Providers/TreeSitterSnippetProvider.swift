//
//  TreeSitterSnippetProvider.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol

/// Supplies intent-gated code snippets and keywords from static per-language tables.
///
/// Each snippet and keyword lists the ``CompletionIntent``s it makes sense for: `for` and `return`
/// at the start of a statement, `nullptr` and `sizeof` where a value is expected, `const` and `int`
/// where a type is, nothing after `.` or `::`. The tables cover C and C++; more languages can be
/// added the same way.
final class TreeSitterSnippetProvider: CompletionProvider {
    /// One snippet table entry.
    struct Snippet {
        let label: String
        /// LSP snippet syntax: `${1:cond}`, `$0`.
        let body: String
        let detail: String
        let intents: Set<CompletionIntent>
    }

    /// One keyword table entry.
    struct Keyword {
        let text: String
        let intents: Set<CompletionIntent>
    }

    let source: CompletionSource = .snippet
    let deadline: Duration = .zero

    func triggerCharacters() -> Set<String> { [] }

    func candidates(for context: CompletionContext, textView: TextViewController) async -> [CompletionCandidate] {
        Self.candidates(languageId: context.languageId, intent: context.intent)
    }

    /// The snippets and keywords offered for `intent` in `languageId`.
    static func candidates(languageId: String, intent: CompletionIntent) -> [CompletionCandidate] {
        var candidates: [CompletionCandidate] = []
        for snippet in snippets[languageId] ?? [] where snippet.intents.contains(intent) {
            candidates.append(
                CompletionCandidate(
                    id: "snippet.\(languageId).\(snippet.label)",
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
        for keyword in keywords[languageId] ?? [] where keyword.intents.contains(intent) {
            candidates.append(
                CompletionCandidate(
                    id: "keyword.\(languageId).\(keyword.text)",
                    label: keyword.text,
                    filterText: keyword.text,
                    sortText: keyword.text,
                    kind: .keyword,
                    source: .keyword,
                    detail: nil,
                    documentation: nil,
                    payload: .plain(insertText: keyword.text)
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

    // MARK: - Keyword tables

    /// Where a declaration or statement can start.
    private static let declarationStarts: Set<CompletionIntent> = [.statement, .topLevel, .typeName, .unknown]
    private static let statementStarts: Set<CompletionIntent> = [.statement, .unknown]
    private static let values: Set<CompletionIntent> = [.expression, .statement, .unknown]
    private static let fileScope: Set<CompletionIntent> = [.topLevel, .unknown]

    private static func keywords(_ texts: [String], _ intents: Set<CompletionIntent>) -> [Keyword] {
        texts.map { Keyword(text: $0, intents: intents) }
    }

    private static let cKeywords: [Keyword] =
        keywords(["if", "else", "for", "while", "do", "switch", "return", "break", "continue", "goto",
                  "case", "default"], statementStarts)
        + keywords(["void", "char", "short", "int", "long", "float", "double", "signed", "unsigned", "bool",
                    "const", "volatile", "struct", "union", "enum", "static", "extern", "register",
                    "inline"], declarationStarts)
        + keywords(["typedef"], statementStarts.union(fileScope))
        + keywords(["sizeof"], values)

    private static let cppKeywords: [Keyword] = cKeywords
        + keywords(["try", "catch", "throw", "delete"], statementStarts)
        + keywords(["using", "static_assert"], statementStarts.union(fileScope))
        + keywords(["class", "typename", "auto", "constexpr", "wchar_t", "char8_t", "char16_t", "char32_t",
                    "mutable", "thread_local", "decltype"], declarationStarts)
        + keywords(["namespace", "template", "public", "private", "protected", "virtual", "override",
                    "explicit", "friend"], fileScope)
        + keywords(["nullptr", "true", "false", "this", "new", "alignof", "noexcept", "static_cast",
                    "dynamic_cast", "reinterpret_cast", "const_cast", "typeid"], values)

    // MARK: - Snippet tables

    private static let cSnippets: [Snippet] = [
        Snippet(
            label: "for",
            body: "for (${1:int i = 0}; ${2:i < n}; ${3:++i}) {\n\t$0\n}",
            detail: "for (init; cond; inc) {…}",
            intents: statementStarts
        ),
        Snippet(
            label: "while",
            body: "while (${1:cond}) {\n\t$0\n}",
            detail: "while (cond) {…}",
            intents: statementStarts
        ),
        Snippet(
            label: "do",
            body: "do {\n\t$0\n} while (${1:cond});",
            detail: "do {…} while (cond);",
            intents: statementStarts
        ),
        Snippet(
            label: "if",
            body: "if (${1:cond}) {\n\t$0\n}",
            detail: "if (cond) {…}",
            intents: statementStarts
        ),
        Snippet(
            label: "else",
            body: "else {\n\t$0\n}",
            detail: "else {…}",
            intents: statementStarts
        ),
        Snippet(
            label: "switch",
            body: "switch (${1:value}) {\ncase ${2:constant}:\n\t$0\n\tbreak;\ndefault:\n\tbreak;\n}",
            detail: "switch (value) {…}",
            intents: statementStarts
        ),
        Snippet(
            label: "struct",
            body: "struct ${1:Name} {\n\t$0\n};",
            detail: "struct Name {…};",
            intents: fileScope
        ),
        Snippet(
            label: "enum",
            body: "enum ${1:Name} {\n\t$0\n};",
            detail: "enum Name {…};",
            intents: fileScope
        ),
        Snippet(
            label: "main",
            body: "int main(int argc, char *argv[]) {\n\t$0\n\treturn 0;\n}",
            detail: "int main(int argc, char *argv[]) {…}",
            intents: fileScope
        ),
        Snippet(
            label: "#include <insert>",
            body: "#include <$0>",
            detail: "Include system header",
            intents: [.preprocessor]
        ),
        Snippet(
            label: "#include \"insert\"",
            body: "#include \"$0\"",
            detail: "Include user header",
            intents: [.preprocessor]
        )
    ]

    private static let cppSnippets: [Snippet] = cSnippets + [
        Snippet(
            label: "class",
            body: "class ${1:Name} {\npublic:\n\t$0\n};",
            detail: "class Name {…};",
            intents: fileScope
        ),
        Snippet(
            label: "namespace",
            body: "namespace ${1:name} {\n\n$0\n\n}",
            detail: "namespace name {…}",
            intents: fileScope
        ),
        Snippet(
            label: "try",
            body: "try {\n\t$0\n} catch (${1:const std::exception &e}) {\n}",
            detail: "try {…} catch (…) {…}",
            intents: statementStarts
        ),
        Snippet(
            label: "for range",
            body: "for (${1:const auto &}${2:item} : ${3:range}) {\n\t$0\n}",
            detail: "for (const auto &item : range) {…}",
            intents: statementStarts
        )
    ]

    private static let keywords: [String: [Keyword]] = [
        "c": cKeywords,
        "cpp": cppKeywords
    ]

    private static let snippets: [String: [Snippet]] = [
        "c": cSnippets,
        "cpp": cppSnippets
    ]
}
