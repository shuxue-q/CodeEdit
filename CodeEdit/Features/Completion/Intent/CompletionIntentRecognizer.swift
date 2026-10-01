//
//  CompletionIntentRecognizer.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import CodeEditSourceEditor
import SwiftTreeSitter

/// Recognizes the user's ``CompletionIntent`` at the cursor.
///
/// Signals are checked strongest first:
/// 1. Comments, string literals, and number literals, from the syntax tree and a lexical scan of the
///    line (an unterminated literal often parses as an `ERROR` node).
/// 2. Preprocessor lines, including `#include` paths.
/// 3. The tokens typed before the prefix on the cursor's line: `obj.`, `ns::`, `return `, `int `,
///    `case `, `vector<`, `void f(`… (see ``CompletionTokenRules``). Incomplete code often parses
///    badly, so the last few tokens are more reliable than the tree there.
/// 4. The innermost enclosing construct in the syntax tree: an argument list, a function body, or
///    file scope.
///
/// Token rules apply to the C family. Other languages get the language-neutral rules (comments,
/// strings, numbers, `.`, `->`, `::`) and the tree scope.
///
/// `nodeTypesAt` is injected so this can be tested without a live `TreeSitterClient`: the
/// production closure walks `TreeSitterClient.nodesAt(location:)`'s node and its ancestors,
/// collecting each `nodeType`, innermost first. Text fallbacks apply when there is no tree.
struct CompletionIntentRecognizer {
    /// Node type names for the language layer(s) at a location, innermost node first.
    let nodeTypesAt: (Int) -> [String]

    /// Creates a recognizer with an injectable node-type lookup, for testing.
    init(nodeTypesAt: @escaping (Int) -> [String]) {
        self.nodeTypesAt = nodeTypesAt
    }

    /// Creates a recognizer backed by a live `TreeSitterClient`.
    @MainActor
    init(treeSitterClient: TreeSitterClient) {
        self.nodeTypesAt = { location in
            guard let results = try? treeSitterClient.nodesAt(location: location) else { return [] }
            var types: [String] = []
            for result in results {
                var node: Node? = result.node
                while let current = node {
                    if let type = current.nodeType {
                        types.append(type)
                    }
                    node = current.parent
                }
            }
            return types
        }
    }

    /// Recognizes the intent at `location`.
    /// - Parameters:
    ///   - location: The cursor's document offset.
    ///   - prefix: The word being typed, up to the cursor.
    ///   - lineTextBeforeCursor: The cursor's line up to the cursor, including `prefix`.
    ///   - languageId: The document's language identifier, for example `"cpp"`.
    func recognize(
        at location: Int,
        prefix: String,
        lineTextBeforeCursor: String,
        languageId: String
    ) -> CompletionIntent {
        let types = nodeTypesAt(location)
        let isCFamily = CFamilyKeywords.languageIds.contains(languageId)
        let beforePrefix = Self.text(lineTextBeforeCursor, droppingSuffix: prefix)
        let scan = CompletionLineScanner.scan(beforePrefix)

        if let intent = literalIntent(
            types: types,
            line: lineTextBeforeCursor,
            beforePrefix: beforePrefix,
            scan: scan,
            isCFamily: isCFamily
        ) {
            return intent
        }
        if prefix.first?.isNumber == true {
            return .numberLiteral
        }
        if types.contains(where: { $0.hasPrefix("preproc") })
            || isCFamily && (prefix.hasPrefix("#") || Self.isPreprocessorLine(beforePrefix)) {
            return .preprocessor
        }

        let scope = Self.scopeIntent(types, isCFamily: isCFamily)
        if isCFamily {
            let input = CompletionTokenRules.Input(
                tokens: scan.tokens,
                hasTrailingSpace: scan.hasTrailingSpace,
                isInFunctionBody: types.contains("compound_statement"),
                allowsIdentifierDeclarations: CFamilyKeywords.identifierDeclarationLanguageIds.contains(languageId)
            )
            if let intent = CompletionTokenRules.intent(for: input) {
                return intent
            }
        } else if let intent = CompletionTokenRules.accessIntent(for: scan.tokens) {
            return intent
        }
        return scope
    }

    // MARK: - Literals

    /// Comments, `#include` paths, and strings. `#include "…"` parses as a string, so the include
    /// check runs before the string check.
    private func literalIntent(
        types: [String],
        line: String,
        beforePrefix: String,
        scan: CompletionLineScanner.Result,
        isCFamily: Bool
    ) -> CompletionIntent? {
        if types.contains(where: { $0.contains("comment") })
            || isCFamily && scan.state.isComment
            || types.isEmpty && Self.looksLikeCommentLine(line, isCFamily: isCFamily) {
            return .comment
        }
        if isCFamily && Self.isIncludePath(beforePrefix) {
            return .includePath
        }
        if types.contains(where: Self.isStringType) || isCFamily && scan.state.isLiteral {
            return .string
        }
        return nil
    }

    private static func isStringType(_ type: String) -> Bool {
        type.contains("string_literal") || type == "string_content" || type == "raw_string_literal"
            || type == "char_literal"
    }

    /// A line that starts inside a block comment (`* text`) or, for other languages, with `//` or
    /// `/*`. Only used when there is no syntax tree.
    private static func looksLikeCommentLine(_ line: String, isCFamily: Bool) -> Bool {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        if !isCFamily && (trimmed.hasPrefix("//") || trimmed.hasPrefix("/*")) {
            return true
        }
        // `* note` continues a block comment; `*ptr = …` is a dereference.
        guard trimmed.hasPrefix("*") else { return false }
        let next = trimmed.dropFirst().first
        return next == nil || next == " " || next == "/"
    }

    /// Whether `line` is inside the path of an `#include <…` / `#import "…` directive.
    static func isIncludePath(_ line: String) -> Bool {
        guard let directive = directiveBody(of: line) else { return false }
        for keyword in ["include_next", "include", "import"] where directive.hasPrefix(keyword) {
            let rest = directive.dropFirst(keyword.count).drop { $0 == " " || $0 == "\t" }
            guard let open = rest.first, open == "<" || open == "\"" else { return false }
            let close: Character = open == "<" ? ">" : "\""
            return !rest.dropFirst().contains(close)
        }
        return false
    }

    /// Whether `line` is a preprocessor directive line.
    private static func isPreprocessorLine(_ line: String) -> Bool {
        directiveBody(of: line) != nil
    }

    /// The text after `#` (and any spaces) on a directive line, or `nil` if `line` is not one.
    private static func directiveBody(of line: String) -> Substring? {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        guard trimmed.hasPrefix("#") else { return nil }
        return trimmed.dropFirst().drop { $0 == " " || $0 == "\t" }
    }

    // MARK: - Scope

    /// Node types that decide the intent when the cursor's tokens are inconclusive, in any language.
    private static let genericScopeIntents: [String: CompletionIntent] = [
        "field_expression": .memberAccess,
        "field_identifier": .memberAccess,
        "type_identifier": .typeName,
        "primitive_type": .typeName,
        "sized_type_specifier": .typeName,
        "type_descriptor": .typeName,
        "compound_statement": .statement,
        "translation_unit": .topLevel
    ]

    /// C-family node types on top of ``genericScopeIntents``. Other grammars reuse some of these
    /// names (CMake's `argument_list`) with a different meaning, so they only apply to the C family.
    private static let cFamilyScopeIntents: [String: CompletionIntent] = genericScopeIntents.merging([
        "parameter_list": .typeName,
        "template_parameter_list": .typeName,
        "template_argument_list": .typeName,
        "argument_list": .expression,
        "condition_clause": .expression,
        "parenthesized_expression": .expression,
        "init_declarator": .expression,
        "initializer_list": .expression,
        "return_statement": .expression,
        "subscript_expression": .expression,
        "field_declaration_list": .topLevel,
        "declaration_list": .topLevel
    ]) { generic, _ in generic }

    /// The intent from the innermost enclosing node the tree knows about.
    static func scopeIntent(_ types: [String], isCFamily: Bool) -> CompletionIntent {
        let intents = isCFamily ? cFamilyScopeIntents : genericScopeIntents
        for type in types {
            if let intent = intents[type] {
                return intent
            }
        }
        return .unknown
    }

    // MARK: - Helpers

    /// `line` without a trailing `suffix` (the typed prefix), when it ends with it.
    private static func text(_ line: String, droppingSuffix suffix: String) -> String {
        guard !suffix.isEmpty, line.hasSuffix(suffix) else { return line }
        return String(line.dropLast(suffix.count))
    }
}
