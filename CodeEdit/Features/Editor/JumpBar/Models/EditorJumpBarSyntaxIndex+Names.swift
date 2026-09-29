//
//  EditorJumpBarSyntaxIndex+Names.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/28/26.
//

import Foundation
import SwiftTreeSitter

extension EditorJumpBarSyntaxIndex {
    static func isIdentifier(_ node: Node) -> Bool {
        identifierTypes.contains(node.nodeType ?? "")
    }

    /// Tree-sitter measures UTF-16 columns in bytes. The editor uses UTF-16 code units.
    static func utf16Column(_ pointColumn: UInt32) -> Int {
        Int(pointColumn / 2)
    }

    static func pointColumn(utf16ZeroBased: Int) -> UInt32 {
        UInt32(max(utf16ZeroBased, 0) * 2)
    }

    func text(of node: Node) -> String? {
        let lower = Int(node.byteRange.lowerBound / 2)
        let upper = Int(node.byteRange.upperBound / 2)
        guard lower >= 0, upper >= lower, upper <= source.utf16.count else { return nil }
        let start = String.Index(utf16Offset: lower, in: source)
        let end = String.Index(utf16Offset: upper, in: source)
        return String(source[start..<end])
    }

    func namedChildren(of node: Node) -> [Node] {
        (0..<node.namedChildCount).compactMap { index in
            guard let child = node.namedChild(at: index), !child.isNull else { return nil }
            return child
        }
    }

    func functionNameNode(_ node: Node) -> Node? {
        if let name = node.child(byFieldName: "name"), !name.isNull, let resolved = declaratorName(name, depth: 0) {
            return resolved
        }
        if let declarator = node.child(byFieldName: "declarator"), !declarator.isNull {
            return declaratorName(declarator, depth: 0)
        }
        return nil
    }

    func variableNameNode(_ node: Node) -> Node? {
        if let name = node.child(byFieldName: "name"), !name.isNull, let resolved = declaratorName(name, depth: 0) {
            return resolved
        }
        if let declarator = node.child(byFieldName: "declarator"), !declarator.isNull {
            return declaratorName(declarator, depth: 0)
        }
        return nil
    }

    func initName(_ node: Node) -> String? {
        for index in 0..<node.childCount {
            guard let child = node.child(at: index), !child.isNull else { continue }
            if child.nodeType == "init" { return "init" }
        }
        return nil
    }

    func contains(_ node: Node, type: String, depth: Int) -> Bool {
        if depth > 5 || node.isNull { return false }
        if node.nodeType == type { return true }
        return namedChildren(of: node).contains { contains($0, type: type, depth: depth + 1) }
    }

    private func declaratorName(_ node: Node, depth: Int) -> Node? {
        if depth > 8 || node.isNull { return nil }
        if Self.isIdentifier(node) { return node }
        let type = node.nodeType ?? ""
        if type == "function_declarator" {
            guard let inner = node.child(byFieldName: "declarator"), !inner.isNull else { return nil }
            return declaratorName(inner, depth: depth + 1)
        }
        if let declarator = node.child(byFieldName: "declarator"), !declarator.isNull {
            return declaratorName(declarator, depth: depth + 1)
        }
        if let name = node.child(byFieldName: "name"), !name.isNull {
            return declaratorName(name, depth: depth + 1)
        }
        if let bound = node.child(byFieldName: "bound_identifier"), !bound.isNull {
            return Self.isIdentifier(bound) ? bound : declaratorName(bound, depth: depth + 1)
        }
        if type == "pattern" {
            return namedChildren(of: node).first { Self.isIdentifier($0) }
        }
        return nil
    }

    static func isCallee(_ node: Node) -> Bool {
        var current: Node? = node
        var hops = 0
        while let cursor = current, !cursor.isNull, hops < 4 {
            guard let parent = cursor.parent, !parent.isNull else { return false }
            let parentType = parent.nodeType ?? ""
            if Self.argumentTypes.contains(parentType) { return false }
            if parentType == "call_expression" || parentType == "call" {
                return callContains(parent, node: node)
            }
            current = parent
            hops += 1
        }
        return false
    }

    private static let argumentTypes: Set<String> = [
        "argument_list", "arguments", "value_arguments", "call_suffix"
    ]

    private static func callContains(_ call: Node, node: Node) -> Bool {
        if let function = call.child(byFieldName: "function"), !function.isNull {
            return range(of: function, contains: node)
        }
        guard let first = call.namedChild(at: 0), !first.isNull else { return false }
        return range(of: first, contains: node)
    }

    private static func range(of outer: Node, contains inner: Node) -> Bool {
        let outerRange = outer.byteRange
        let innerRange = inner.byteRange
        return innerRange.lowerBound >= outerRange.lowerBound && innerRange.upperBound <= outerRange.upperBound
    }
}
