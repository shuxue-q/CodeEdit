//
//  DartCompletionTables.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/13/26.
//

/// The keyword and snippet tables for Dart, used by ``TreeSitterSnippetProvider`` under the language
/// id `dart`.
///
/// Each entry lists the intents it is offered for (see ``DartTokenRules``):
///
/// - Statement keywords (`if`, `return`, `try`) and snippets: at the start of a statement in a function
///   body (``CompletionIntent/statement``).
/// - Declaration keywords (`final`, `late`, `void`): where a statement or a member can start.
/// - Directives, type declarations, and member modifiers (`import`, `class`, `static`, `factory`): at
///   file and class scope (``CompletionIntent/topLevel``), with the widget, `build`, and `main` snippets.
/// - Values (`true`, `null`, `this`, `const`): where a value is expected, including a call's
///   arguments (``CompletionIntent/argument``).
/// - Parameter modifiers (`required`, `covariant`, `this`, `super`): in a parameter list, which is a
///   type position (``CompletionIntent/typeName``).
///
/// ``CompletionIntent/unknown`` covers a document without a syntax tree. Types such as `int` and
/// `String` are left to the analysis server, which offers them as classes. Snippet bodies use the LSP
/// syntax and two-space indentation, Dart's convention.
enum DartCompletionTables {
    typealias Keyword = TreeSitterSnippetProvider.Keyword
    typealias Snippet = TreeSitterSnippetProvider.Snippet

    /// Where a statement can start.
    private static let statementStarts: Set<CompletionIntent> = [.statement, .unknown]
    /// Where a statement or a member can start.
    private static let declarationStarts: Set<CompletionIntent> = [.statement, .topLevel, .unknown]
    /// File and class scope.
    private static let fileScope: Set<CompletionIntent> = [.topLevel, .unknown]
    /// Where a value can go.
    private static let values: Set<CompletionIntent> = [.expression, .statement, .argument, .unknown]
    /// A parameter list or another type position.
    private static let types: Set<CompletionIntent> = [.typeName]

    private static func keywords(_ texts: [String], _ intents: Set<CompletionIntent>) -> [Keyword] {
        texts.map { Keyword(text: $0, intents: intents) }
    }

    // MARK: - Keywords

    /// All keyword entries. Each keyword is listed once, with every intent it is offered for.
    static let keywords: [Keyword] =
        keywords(["if", "else", "for", "while", "do", "switch", "case", "default", "return", "break",
                  "continue", "try", "rethrow", "assert", "yield"], statementStarts)
        + keywords(["var", "final", "late"], declarationStarts)
        + keywords(["void", "dynamic"], declarationStarts.union(types))
        + keywords(["const"], declarationStarts.union(values))
        + keywords(["throw", "await"], values)
        + keywords(["true", "false", "null"], values)
        + keywords(["this", "super"], values.union(types))
        + keywords(["required", "covariant"], types)
        + keywords(["import", "export", "part", "library", "class", "enum", "mixin", "extension", "typedef",
                    "abstract", "sealed", "base", "interface", "static", "factory", "external", "operator",
                    "get", "set"], fileScope)

    // MARK: - Snippets

    /// All snippet entries.
    static let snippets: [Snippet] = [
        Snippet(
            label: "stless",
            body: "class ${1:MyWidget} extends StatelessWidget {\n  const ${1:MyWidget}({super.key});\n\n"
                + "  @override\n  Widget build(BuildContext context) {\n    return ${2:const Placeholder()};\n"
                + "  }\n}",
            detail: "StatelessWidget subclass",
            intents: fileScope
        ),
        Snippet(
            label: "stful",
            body: "class ${1:MyWidget} extends StatefulWidget {\n  const ${1:MyWidget}({super.key});\n\n"
                + "  @override\n  State<${1:MyWidget}> createState() => _${1:MyWidget}State();\n}\n\n"
                + "class _${1:MyWidget}State extends State<${1:MyWidget}> {\n  @override\n"
                + "  Widget build(BuildContext context) {\n    return ${2:const Placeholder()};\n  }\n}",
            detail: "StatefulWidget subclass and its State",
            intents: fileScope
        ),
        Snippet(
            label: "build",
            body: "@override\nWidget build(BuildContext context) {\n  return ${1:const Placeholder()};\n}",
            detail: "Widget build(BuildContext context) {…}",
            intents: fileScope
        ),
        Snippet(
            label: "main",
            body: "void main() {\n  $0\n}",
            detail: "void main() {…}",
            intents: fileScope
        ),
        Snippet(
            label: "for",
            body: "for (var ${1:i} = 0; ${1:i} < ${2:count}; ${1:i}++) {\n  $0\n}",
            detail: "for (var i = 0; i < count; i++) {…}",
            intents: statementStarts
        ),
        Snippet(
            label: "forin",
            body: "for (final ${1:item} in ${2:items}) {\n  $0\n}",
            detail: "for (final item in items) {…}",
            intents: statementStarts
        ),
        Snippet(
            label: "if",
            body: "if (${1:condition}) {\n  $0\n}",
            detail: "if (condition) {…}",
            intents: statementStarts
        ),
        Snippet(
            label: "switch",
            body: "switch (${1:value}) {\n  case ${2:pattern}:\n    $0\n}",
            detail: "switch (value) {…}",
            intents: statementStarts
        ),
        Snippet(
            label: "try",
            body: "try {\n  $0\n} catch (${1:e}) {\n}",
            detail: "try {…} catch (e) {…}",
            intents: statementStarts
        )
    ]
}
