//
//  SyntacticContextResolver.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import CodeEditSourceEditor
import SwiftTreeSitter

/// Resolves the ``SyntacticContext`` at a document offset from the tree-sitter node ancestry.
///
/// `nodeTypesAt` is injected so this can be tested without a live `TreeSitterClient`: the
/// production closure walks `TreeSitterClient.nodesAt(location:)`'s node and its ancestors,
/// collecting each `nodeType`. Text fallbacks apply when there is no tree (`nodeTypesAt` returns `[]`).
struct SyntacticContextResolver {
    /// Node type names for the language layer(s) at a location, innermost node first.
    let nodeTypesAt: (Int) -> [String]

    /// Creates a resolver with an injectable node-type lookup, for testing.
    init(nodeTypesAt: @escaping (Int) -> [String]) {
        self.nodeTypesAt = nodeTypesAt
    }

    /// Creates a resolver backed by a live `TreeSitterClient`.
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

    /// Resolves the syntactic context at `location`, given the already-computed `prefix` and the
    /// raw line text up to the cursor (used for the text fallback when there is no tree).
    func resolve(at location: Int, prefix: String, lineTextBeforeCursor: String) -> SyntacticContext {
        let types = nodeTypesAt(location)

        if types.isEmpty {
            return textFallback(prefix: prefix, lineTextBeforeCursor: lineTextBeforeCursor)
        }

        if types.contains(where: { $0.contains("comment") }) {
            return .comment
        }
        if types.contains(where: { isStringType($0) }) {
            return .string
        }
        if types.contains(where: { $0.hasPrefix("preproc") }) {
            return .preprocessor
        }
        // Incomplete code such as `std::` often parses as an ERROR node inside a declaration or
        // statement, so check the text for a scope/member operator before the node ancestry.
        if Self.followsAccessOperator(prefix: prefix, lineTextBeforeCursor: lineTextBeforeCursor) {
            return .memberAccess
        }
        if types.contains(where: { $0 == "field_expression" || $0 == "field_identifier" }) {
            return .memberAccess
        }
        if types.contains(where: { Self.typePositionTypes.contains($0) }) {
            return .typePosition
        }
        if types.contains(where: { $0 == "compound_statement" }) {
            return .statement
        }
        if types.contains(where: { $0 == "translation_unit" }) {
            return .topLevel
        }
        return .unknown
    }

    private func isStringType(_ type: String) -> Bool {
        type.contains("string_literal") || type == "string_content" || type == "raw_string_literal"
    }

    private func textFallback(prefix: String, lineTextBeforeCursor: String) -> SyntacticContext {
        let trimmed = lineTextBeforeCursor.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") || prefix.hasPrefix("#") {
            return .preprocessor
        }
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") {
            return .comment
        }
        if Self.followsAccessOperator(prefix: prefix, lineTextBeforeCursor: lineTextBeforeCursor) {
            return .memberAccess
        }
        return .unknown
    }

    /// Whether the text before the typed `prefix` ends with `.`, `->`, or `::`.
    private static func followsAccessOperator(prefix: String, lineTextBeforeCursor: String) -> Bool {
        let beforePrefix = lineTextBeforeCursor.hasSuffix(prefix)
            ? lineTextBeforeCursor.dropLast(prefix.count)
            : Substring(lineTextBeforeCursor)
        return beforePrefix.hasSuffix(".") || beforePrefix.hasSuffix("->") || beforePrefix.hasSuffix("::")
    }

    private static let typePositionTypes: Set<String> = [
        "type_identifier",
        "primitive_type",
        "sized_type_specifier",
        "type_descriptor"
    ]
}
