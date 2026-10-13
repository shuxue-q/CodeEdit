//
//  DartKeywords.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/13/26.
//

/// The Dart vocabulary used to recognize completion intent: which language ids the Dart rules apply
/// to, which keywords decide the intent, and which node types of the vendored `tree-sitter-dart`
/// grammar mean what.
enum DartKeywords {
    /// Language identifiers the Dart rules apply to, in the editor's `CodeLanguage` ids and in the
    /// analysis server's.
    static let languageIds: Set<String> = ["dart"]

    /// Keywords after which a type follows: `new Foo`, `x is Foo`, `as Foo`, `extends Foo`,
    /// `implements Foo`, `with Mixin`, `on Exception`, `mixin M on Base`.
    static let typeLeads: Set<String> = ["new", "is", "as", "extends", "implements", "with", "on"]

    /// Keywords that start a variable declaration, after which its name (or its type) follows.
    static let declarationLeads: Set<String> = ["var", "final", "const", "late"]

    /// Keywords after which the name of a new type or library follows.
    static let typeDeclarationLeads: Set<String> = [
        "class", "enum", "mixin", "extension", "typedef", "library"
    ]

    /// Keywords after which only a value can follow.
    static let expressionLeads: Set<String> = ["return", "throw", "await", "yield", "in", "assert"]

    /// Modifiers after which a type (or `final`, `const`, `var`) follows: `static int`,
    /// `required String`, `covariant Foo`.
    static let typeModifiers: Set<String> = ["static", "required", "covariant", "external", "factory"]

    /// Class modifiers, after which `class`, `mixin`, or another modifier follows.
    static let classModifiers: Set<String> = ["abstract", "sealed", "base", "interface"]

    /// The intent after a keyword and a space, for keywords that fully decide it. `const` is not here:
    /// it starts a declaration at statement start but a constant constructor call in an expression.
    static let intentAfterKeyword: [String: CompletionIntent] = {
        var intents: [String: CompletionIntent] = ["case": .caseLabel, "else": .statement, "do": .statement]
        for keyword in classModifiers {
            intents[keyword] = .topLevel
        }
        for keyword in typeLeads.union(typeModifiers) {
            intents[keyword] = .typeName
        }
        for keyword in typeDeclarationLeads.union(["var", "final", "late"]) {
            intents[keyword] = .declarationName
        }
        for keyword in expressionLeads {
            intents[keyword] = .expression
        }
        return intents
    }()

    /// The intent right after `keyword(`, for keywords whose parentheses are not a call.
    static let intentInsideParens: [String: CompletionIntent] = [
        "if": .expression, "while": .expression, "switch": .expression, "assert": .expression,
        "for": .statement, "catch": .declarationName
    ]

    /// Keywords that cannot appear in a type, so a phrase holding one is not a declaration's type.
    static let nonTypeKeywords: Set<String> = expressionLeads.union(typeLeads).union(typeDeclarationLeads).union([
        "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "try", "catch",
        "finally", "rethrow", "true", "false", "null", "this", "super", "import", "export", "part", "show",
        "hide", "async", "sync", "operator", "get", "set"
    ])

    /// Tokens that end the previous declaration or expression, so a new type may start after them.
    static let segmentBoundaries: Set<String> = [";", "}", ",", "=", "=>", ":", "??"]

    /// Directives whose string is a URI: completing it offers libraries and files.
    static let uriDirectives: Set<String> = ["import", "export", "part"]

    // MARK: - Syntax tree

    /// Node types for comments.
    static let commentNodes: Set<String> = ["comment", "documentation_comment"]

    /// Node types that decide the intent when the cursor's tokens are inconclusive, innermost first.
    ///
    /// `label` is the name of a named argument (`pad|: x`); `named_argument` without a `label` inside
    /// it is the value after the colon. The `block` of a function or closure is a statement position;
    /// class, mixin, extension, and enum bodies are declaration positions, like the file itself.
    static let scopeIntents: [String: CompletionIntent] = [
        "label": .argument,
        "named_argument": .expression,
        "arguments": .argument,
        "argument_part": .argument,
        "formal_parameter_list": .typeName,
        "optional_formal_parameters": .typeName,
        "formal_parameter": .typeName,
        "type_arguments": .typeName,
        "type_parameters": .typeName,
        "list_literal": .expression,
        "set_or_map_literal": .expression,
        "parenthesized_expression": .expression,
        "return_statement": .expression,
        "block": .statement,
        "function_body": .statement,
        "function_expression_body": .statement,
        "switch_block": .statement,
        "class_body": .topLevel,
        "extension_body": .topLevel,
        "enum_body": .topLevel,
        "program": .topLevel
    ]

    /// The intent from the innermost node type the table knows. `ERROR` and anonymous nodes (`)`,
    /// `;`) are skipped, so incomplete code resolves through the first real ancestor.
    static func scopeIntent(_ types: [String]) -> CompletionIntent? {
        for type in types {
            if let intent = scopeIntents[type] {
                return intent
            }
        }
        return nil
    }
}
