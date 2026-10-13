//
//  RustCompletionTables.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/13/26.
//

/// The keyword and snippet tables for Rust, used by ``TreeSitterSnippetProvider`` under the language id
/// `rust`.
///
/// Each entry lists the intents it is offered for (see ``RustTokenRules``):
///
/// - Control flow (`if`, `match`, `loop`, `return`) and the statement snippets: at the start of a statement
///   in a block (``CompletionIntent/statement``).
/// - Items (`fn`, `struct`, `impl`, `use`, `mod`) and the item snippets: at file scope and in `impl`, `trait`,
///   and `mod` bodies (``CompletionIntent/topLevel``). Items may also start a statement.
/// - Values (`true`, `None`, `Some`, `self`, `move`): where a value is expected
///   (``CompletionIntent/expression``) and at a statement start.
/// - `dyn`, `impl`, `mut`, and `Self` in a type position (``CompletionIntent/typeName``).
///
/// Nothing is offered after `.` or `::`, or inside an attribute. ``CompletionIntent/unknown`` covers a
/// document without a syntax tree. Primitive and library types come from rust-analyzer. Snippet bodies use
/// the LSP syntax and four-space indentation, Rust's convention.
enum RustCompletionTables {
    typealias Keyword = TreeSitterSnippetProvider.Keyword
    typealias Snippet = TreeSitterSnippetProvider.Snippet

    /// Where a statement can start.
    private static let statementStarts: Set<CompletionIntent> = [.statement, .unknown]
    /// Where an item can start: file scope, `impl`/`trait`/`mod` bodies, and blocks.
    private static let itemStarts: Set<CompletionIntent> = [.topLevel, .statement, .unknown]
    /// File scope and `impl`/`trait`/`mod` bodies.
    private static let itemScope: Set<CompletionIntent> = [.topLevel, .unknown]
    /// Where a value can go.
    private static let values: Set<CompletionIntent> = [.expression, .statement, .unknown]
    /// A type position.
    private static let types: Set<CompletionIntent> = [.typeName]

    private static func keywords(_ texts: [String], _ intents: Set<CompletionIntent>) -> [Keyword] {
        texts.map { Keyword(text: $0, intents: intents) }
    }

    // MARK: - Keywords

    /// All keyword entries. Each keyword is listed once, with every intent it is offered for.
    static let keywords: [Keyword] =
        keywords(["while", "for", "let", "return", "break", "continue", "else"], statementStarts)
        + keywords(["if", "match", "loop"], values)
        + keywords(["fn", "struct", "enum", "trait", "type", "const", "static", "use", "unsafe", "async"], itemStarts)
        + keywords(["impl"], itemStarts.union(types))
        + keywords(["mod", "pub", "extern", "union", "macro_rules!"], itemScope)
        + keywords(["true", "false", "self", "None", "Some", "Ok", "Err", "move"], values)
        + keywords(["Self"], values.union(types))
        + keywords(["dyn", "mut"], types)

    // MARK: - Snippets

    /// All snippet entries.
    static let snippets: [Snippet] = [
        Snippet(
            label: "fn",
            body: "fn ${1:name}(${2}) {\n    $0\n}",
            detail: "fn name() {…}",
            intents: itemStarts
        ),
        Snippet(
            label: "impl",
            body: "impl ${1:Type} {\n    $0\n}",
            detail: "impl Type {…}",
            intents: itemScope
        ),
        Snippet(
            label: "struct",
            body: "struct ${1:Name} {\n    $0\n}",
            detail: "struct Name {…}",
            intents: itemScope
        ),
        Snippet(
            label: "enum",
            body: "enum ${1:Name} {\n    $0\n}",
            detail: "enum Name {…}",
            intents: itemScope
        ),
        Snippet(
            label: "trait",
            body: "trait ${1:Name} {\n    $0\n}",
            detail: "trait Name {…}",
            intents: itemScope
        ),
        Snippet(
            label: "main",
            body: "fn main() {\n    $0\n}",
            detail: "fn main() {…}",
            intents: itemScope
        ),
        Snippet(
            label: "test",
            body: "#[test]\nfn ${1:name}() {\n    $0\n}",
            detail: "#[test] fn name() {…}",
            intents: itemScope
        ),
        Snippet(
            label: "derive",
            body: "#[derive(${1:Debug})]",
            detail: "#[derive(Debug)]",
            intents: itemScope
        ),
        Snippet(
            label: "mod tests",
            body: "#[cfg(test)]\nmod tests {\n    use super::*;\n\n    #[test]\n    fn ${1:it_works}() {\n"
                + "        $0\n    }\n}",
            detail: "#[cfg(test)] mod tests {…}",
            intents: itemScope
        ),
        Snippet(
            label: "match",
            body: "match ${1:value} {\n    ${2:pattern} => $0,\n}",
            detail: "match value {…}",
            intents: statementStarts
        ),
        Snippet(
            label: "if let",
            body: "if let ${1:Some(value)} = ${2:option} {\n    $0\n}",
            detail: "if let Some(value) = option {…}",
            intents: statementStarts
        ),
        Snippet(
            label: "while let",
            body: "while let ${1:Some(value)} = ${2:iterator.next()} {\n    $0\n}",
            detail: "while let Some(value) = iterator.next() {…}",
            intents: statementStarts
        ),
        Snippet(
            label: "loop",
            body: "loop {\n    $0\n}",
            detail: "loop {…}",
            intents: statementStarts
        ),
        Snippet(
            label: "for",
            body: "for ${1:item} in ${2:iter} {\n    $0\n}",
            detail: "for item in iter {…}",
            intents: statementStarts
        )
    ]
}
