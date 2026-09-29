//
//  EditorJumpBarSyntaxIndex+Walk.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/28/26.
//

import Foundation
import SwiftTreeSitter

extension EditorJumpBarSyntaxIndex {
    static let functionTypes: Set<String> = [
        "function_definition",
        "function_declaration",
        "method_definition",
        "method_declaration",
        "function_item",
        "constructor_declaration",
        "arrow_function"
    ]

    static let variableTypes: Set<String> = [
        "declaration",
        "init_declarator",
        "parameter_declaration",
        "field_declaration",
        "property_declaration",
        "parameter",
        "optional_parameter",
        "required_parameter",
        "formal_parameter",
        "for_range_loop",
        "variable_declarator",
        "lexical_declaration",
        "short_var_declaration"
    ]

    static let identifierTypes: Set<String> = [
        "identifier",
        "field_identifier",
        "simple_identifier",
        "property_identifier"
    ]

    func walk(
        _ node: Node,
        parentFunction: String?,
        into collected: inout [EditorJumpBarSyntaxSymbol]
    ) {
        guard visited < Self.maxNodes, !node.isNull else { return }
        visited += 1
        let type = node.nodeType ?? ""
        if Self.functionTypes.contains(type),
           let functionID = recordFunction(node, parent: parentFunction, into: &collected) {
            namedChildren(of: node).forEach { walk($0, parentFunction: functionID, into: &collected) }
            return
        }
        if Self.variableTypes.contains(type) {
            recordVariable(node, parent: parentFunction, into: &collected)
        }
        namedChildren(of: node).forEach { walk($0, parentFunction: parentFunction, into: &collected) }
    }

    private func recordFunction(
        _ node: Node,
        parent: String?,
        into collected: inout [EditorJumpBarSyntaxSymbol]
    ) -> String? {
        let nameNode = functionNameNode(node)
        let name = nameNode.flatMap { text(of: $0) } ?? initName(node)
        guard let name, !name.isEmpty else { return nil }
        let symbol = makeSymbol(
            Draft(name: name, kind: .function, nameNode: nameNode, owner: node, parent: parent),
            ordinal: collected.count
        )
        collected.append(symbol)
        return symbol.id
    }

    private func recordVariable(
        _ node: Node,
        parent: String?,
        into collected: inout [EditorJumpBarSyntaxSymbol]
    ) {
        let type = node.nodeType ?? ""
        if contains(node, type: "function_declarator", depth: 0) { return }
        if type == "declaration" || type == "field_declaration" || type == "lexical_declaration" {
            let hasInnerDeclarator = contains(node, type: "init_declarator", depth: 0)
                || contains(node, type: "variable_declarator", depth: 0)
            if hasInnerDeclarator { return }
        }
        guard let nameNode = variableNameNode(node), let name = text(of: nameNode), !name.isEmpty else { return }
        collected.append(
            makeSymbol(
                Draft(name: name, kind: .variable, nameNode: nameNode, owner: node, parent: parent),
                ordinal: collected.count
            )
        )
    }

    private struct Draft {
        let name: String
        let kind: EditorJumpBarSyntaxSymbol.Kind
        let nameNode: Node?
        let owner: Node
        let parent: String?
    }

    private func makeSymbol(_ draft: Draft, ordinal: Int) -> EditorJumpBarSyntaxSymbol {
        let namePoint = draft.nameNode?.pointRange.lowerBound ?? draft.owner.pointRange.lowerBound
        let start = draft.owner.pointRange.lowerBound
        let end = draft.owner.pointRange.upperBound
        return EditorJumpBarSyntaxSymbol(
            id: "\(draft.kind):\(draft.parent ?? "root"):\(ordinal):\(draft.name):\(namePoint.row)",
            name: draft.name,
            kind: draft.kind,
            nameLine: Int(namePoint.row) + 1,
            nameColumn: Self.utf16Column(namePoint.column) + 1,
            startLine: Int(start.row) + 1,
            startColumn: Self.utf16Column(start.column) + 1,
            endLine: Int(end.row) + 1,
            endColumn: Self.utf16Column(end.column) + 1,
            parentID: draft.parent
        )
    }
}
