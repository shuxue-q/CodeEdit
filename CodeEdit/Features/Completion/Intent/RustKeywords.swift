//
//  RustKeywords.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/13/26.
//

/// The Rust vocabulary used to recognize completion intent: which language ids the Rust rules apply to,
/// which keywords decide the intent, and which node types of the vendored `tree-sitter-rust` grammar mean
/// what.
enum RustKeywords {
    /// Language identifiers the Rust rules apply to, in the editor's `CodeLanguage` ids and in
    /// rust-analyzer's.
    static let languageIds: Set<String> = ["rust"]

    /// Keywords after which the name of a new item or binding follows: `let x`, `fn name`, `struct Name`.
    /// `mut`, `const`, and `for` depend on what precedes them and are decided by ``RustTokenRules``.
    static let declarationLeads: Set<String> = [
        "let", "fn", "struct", "enum", "union", "trait", "mod", "static", "type", "ref", "crate"
    ]

    /// Keywords after which a type follows: `impl Display`, `dyn Error`, `x as u32`, `where T`.
    static let typeLeads: Set<String> = ["impl", "dyn", "as", "where"]

    /// Keywords after which only a value can follow.
    static let expressionLeads: Set<String> = [
        "return", "if", "while", "match", "in", "break", "yield", "move", "become"
    ]

    /// Keywords after which another keyword or an item follows: `pub fn`, `unsafe impl`, `extern "C"`.
    static let itemModifiers: Set<String> = ["pub", "unsafe", "async", "extern", "default", "auto"]

    /// Keywords that cannot name a struct in a struct literal (`Point { x: 1 }`), so a `{` after them opens
    /// a block or a body.
    static let blockKeywords: Set<String> = [
        "if", "else", "while", "for", "loop", "match", "unsafe", "async", "move", "fn", "impl", "trait", "mod",
        "struct", "enum", "union", "where", "extern", "const", "static", "in", "return", "break", "let", "use"
    ]

    /// The intent after a keyword and a space, for keywords that fully decide it.
    static let intentAfterKeyword: [String: CompletionIntent] = {
        var intents: [String: CompletionIntent] = ["else": .statement, "use": .scopeAccess]
        for keyword in declarationLeads {
            intents[keyword] = .declarationName
        }
        for keyword in typeLeads {
            intents[keyword] = .typeName
        }
        for keyword in expressionLeads {
            intents[keyword] = .expression
        }
        return intents
    }()

    // MARK: - Syntax tree

    /// Node types for comments, including documentation comments.
    static let commentNodes: Set<String> = ["line_comment", "block_comment", "doc_comment"]

    /// Innermost node types with the cursor inside a string's text, so a string that started on an earlier
    /// line is still a string. The vendored grammar has no node for the text itself: the literal is innermost
    /// there, while on one of its quotes the quote is. Newer grammars add `string_content`.
    static let stringContentNodes: Set<String> = ["string_literal", "raw_string_literal", "string_content"]

    /// Node types that decide the intent when the cursor's tokens are inconclusive, innermost first.
    ///
    /// A `block` (a function body, a closure's or an `if`'s braces) is a statement position. The file and
    /// the bodies of `impl`, `trait`, `mod`, and `extern` blocks (`declaration_list`) are item positions.
    /// A struct's or enum's body starts a field or variant name; a struct literal's braces a field value.
    static let scopeIntents: [String: CompletionIntent] = [
        "attribute_item": .preprocessor,
        "inner_attribute_item": .preprocessor,
        "attribute": .preprocessor,
        "use_declaration": .scopeAccess,
        "use_list": .scopeAccess,
        "scoped_use_list": .scopeAccess,
        "token_tree": .expression,
        "arguments": .expression,
        "array_expression": .expression,
        "tuple_expression": .expression,
        "parenthesized_expression": .expression,
        "return_expression": .expression,
        "field_initializer_list": .expression,
        "match_block": .expression,
        "type_arguments": .typeName,
        "type_parameters": .typeName,
        "where_clause": .typeName,
        "trait_bounds": .typeName,
        "ordered_field_declaration_list": .typeName,
        "parameters": .declarationName,
        "closure_parameters": .declarationName,
        "field_declaration_list": .declarationName,
        "enum_variant_list": .declarationName,
        "block": .statement,
        "declaration_list": .topLevel,
        "source_file": .topLevel
    ]

    /// The intent from the innermost node type the table knows. `ERROR` and anonymous nodes (`)`, `;`)
    /// are skipped, so incomplete code resolves through the first real ancestor.
    static func scopeIntent(_ types: [String]) -> CompletionIntent? {
        for type in types {
            if let intent = scopeIntents[type] {
                return intent
            }
        }
        return nil
    }
}
