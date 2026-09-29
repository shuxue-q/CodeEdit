//
//  EditorJumpBarSyntaxIndex.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/28/26.
//

import Foundation
import CodeEditLanguages
import CodeEditSourceEditor
import SwiftTreeSitter

/// A function or variable name found by walking the syntax tree.
///
/// Language servers omit local variables from document symbols, so the jump bar reads them from the tree.
struct EditorJumpBarSyntaxSymbol: Identifiable, Hashable {
    enum Kind: Hashable {
        case function
        case variable
    }

    let id: String
    let name: String
    let kind: Kind
    let nameLine: Int
    let nameColumn: Int
    let startLine: Int
    let startColumn: Int
    let endLine: Int
    let endColumn: Int
    let parentID: String?

    var systemImage: String {
        kind == .function ? "f.square" : "v.square"
    }

    func contains(line: Int, column: Int) -> Bool {
        let afterStart = line > startLine || (line == startLine && column >= startColumn)
        let beforeEnd = line < endLine || (line == endLine && column < endColumn)
        return afterStart && beforeEnd
    }
}

/// Indexes function and variable declaration names for one source buffer.
final class EditorJumpBarSyntaxIndex {
    private(set) var symbols: [EditorJumpBarSyntaxSymbol] = []

    private var tree: MutableTree?
    var source: String = ""
    var visited = 0

    private static let maxSourceLength = 400_000
    static let maxNodes = 20_000

    func clear() {
        symbols = []
        tree = nil
        source = ""
        visited = 0
    }

    func rebuild(source: String, language: CodeLanguage) {
        clear()
        guard source.count <= Self.maxSourceLength, let parserLanguage = language.language else { return }
        let parser = Parser()
        guard (try? parser.setLanguage(parserLanguage)) != nil, let parsed = parser.parse(source) else { return }
        self.source = source
        tree = parsed
        guard let root = parsed.rootNode, !root.isNull else { return }
        var collected: [EditorJumpBarSyntaxSymbol] = []
        walk(root, parentFunction: nil, into: &collected)
        symbols = collected
    }

    /// The variable name under `cursor`, or `nil` when the caret is on a function name or a call.
    func variable(at cursor: CursorPosition?) -> EditorJumpBarSyntaxSymbol? {
        guard let cursor, cursor.start.line > 0, cursor.start.column > 0 else { return nil }
        guard let root = tree?.rootNode, !root.isNull else { return nil }
        guard let ident = identifier(at: cursor, root: root) else { return nil }
        if Self.isCallee(ident) { return nil }
        guard let name = text(of: ident), !name.isEmpty else { return nil }
        let line = Int(ident.pointRange.lowerBound.row) + 1
        let column = Self.utf16Column(ident.pointRange.lowerBound.column) + 1
        if symbols.contains(where: { $0.kind == .function && $0.nameLine == line && $0.nameColumn == column }) {
            return nil
        }
        if let declared = symbols.first(where: {
            $0.kind == .variable && $0.nameLine == line && $0.nameColumn == column
        }) {
            return declared
        }
        let parent = symbols.last {
            $0.kind == .function && $0.contains(line: cursor.start.line, column: cursor.start.column)
        }
        return EditorJumpBarSyntaxSymbol(
            id: "use:\(name):\(line):\(column)",
            name: name,
            kind: .variable,
            nameLine: line,
            nameColumn: column,
            startLine: line,
            startColumn: column,
            endLine: line,
            endColumn: column + name.utf16.count,
            parentID: parent?.id
        )
    }

    private func identifier(at cursor: CursorPosition, root: Node) -> Node? {
        let row = UInt32(cursor.start.line - 1)
        let column = Self.pointColumn(utf16ZeroBased: cursor.start.column - 1)
        let start = Point(row: row, column: column)
        let end = Point(row: row, column: column + 2)
        guard let leaf = root.descendant(in: start..<end), !leaf.isNull else { return nil }
        if Self.isIdentifier(leaf) { return leaf }
        if let parent = leaf.parent, !parent.isNull, Self.isIdentifier(parent) { return parent }
        return nil
    }
}
