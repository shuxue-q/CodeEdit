//
//  EditorJumpBarPath.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/28/26.
//

import Foundation
import CodeEditSourceEditor

/// One crumb after the file path. `items` are the siblings shown when the crumb is clicked.
struct JumpBarPathSegment: Identifiable, Hashable {
    struct Item: Identifiable, Hashable {
        let id: String
        let title: String
        let systemImage: String
        let line: Int
        let column: Int
    }

    enum Role: Hashable {
        case function
        case variable
        case scope
        case placeholder
    }

    let id: String
    let title: String
    let systemImage: String
    let role: Role
    let items: [Item]
}

/// Builds the symbol crumbs: enclosing scopes, then the function, then the variable under the cursor.
@MainActor
enum EditorJumpBarPath {
    static func segments(
        documentSymbols: [JumpBarSymbol],
        syntaxSymbols: [EditorJumpBarSyntaxSymbol],
        cursorVariable: EditorJumpBarSyntaxSymbol?,
        cursor: CursorPosition?
    ) -> [JumpBarPathSegment] {
        let chain = EditorJumpBarSymbolModel.enclosingChain(in: documentSymbols, cursor: cursor)
        var result = chain.map { segment(for: $0, in: documentSymbols) }
        if result.isEmpty {
            result.append(contentsOf: syntaxFunctionSegments(syntaxSymbols, cursor: cursor))
        }
        if let cursorVariable, !alreadyShows(cursorVariable, chain: chain) {
            result.append(variableSegment(cursorVariable, syntaxSymbols: syntaxSymbols))
        }
        if result.isEmpty {
            result.append(placeholder(documentSymbols: documentSymbols, syntaxSymbols: syntaxSymbols))
        }
        return result
    }

    private static func segment(for symbol: JumpBarSymbol, in symbols: [JumpBarSymbol]) -> JumpBarPathSegment {
        let peers = EditorJumpBarSymbolModel.siblings(of: symbol, in: symbols).filter { symbol.sharesMenu(with: $0) }
        return JumpBarPathSegment(
            id: symbol.id,
            title: symbol.pathTitle,
            systemImage: symbol.systemImage,
            role: role(of: symbol),
            items: peers.map(item(for:))
        )
    }

    private static func role(of symbol: JumpBarSymbol) -> JumpBarPathSegment.Role {
        if symbol.isFunction { return .function }
        if symbol.isVariable { return .variable }
        return .scope
    }

    private static func item(for symbol: JumpBarSymbol) -> JumpBarPathSegment.Item {
        JumpBarPathSegment.Item(
            id: symbol.id,
            title: symbol.pathTitle,
            systemImage: symbol.systemImage,
            line: symbol.line,
            column: symbol.column
        )
    }

    private static func syntaxFunctionSegments(
        _ symbols: [EditorJumpBarSyntaxSymbol],
        cursor: CursorPosition?
    ) -> [JumpBarPathSegment] {
        guard let cursor else { return [] }
        let functions = symbols.filter { $0.kind == .function }
        guard let function = functions.last(where: {
            $0.contains(line: cursor.start.line, column: cursor.start.column)
        }) else { return [] }
        let peers = functions.filter { $0.parentID == function.parentID }
        return [syntaxSegment(function, peers: peers, role: .function)]
    }

    private static func variableSegment(
        _ variable: EditorJumpBarSyntaxSymbol,
        syntaxSymbols: [EditorJumpBarSyntaxSymbol]
    ) -> JumpBarPathSegment {
        var peers = syntaxSymbols.filter { $0.kind == .variable && $0.parentID == variable.parentID }
        if !peers.contains(where: { $0.name == variable.name }) {
            peers.append(variable)
        }
        peers = dedupe(peers)
        return syntaxSegment(variable, peers: peers, role: .variable)
    }

    private static func syntaxSegment(
        _ symbol: EditorJumpBarSyntaxSymbol,
        peers: [EditorJumpBarSyntaxSymbol],
        role: JumpBarPathSegment.Role
    ) -> JumpBarPathSegment {
        JumpBarPathSegment(
            id: symbol.id,
            title: symbol.name,
            systemImage: symbol.systemImage,
            role: role,
            items: peers.map { peer in
                JumpBarPathSegment.Item(
                    id: peer.id,
                    title: peer.name,
                    systemImage: peer.systemImage,
                    line: peer.nameLine,
                    column: peer.nameColumn
                )
            }
        )
    }

    private static func alreadyShows(_ variable: EditorJumpBarSyntaxSymbol, chain: [JumpBarSymbol]) -> Bool {
        guard let last = chain.last, last.isVariable else { return false }
        return last.name == variable.name
    }

    private static func dedupe(_ symbols: [EditorJumpBarSyntaxSymbol]) -> [EditorJumpBarSyntaxSymbol] {
        var seen: Set<String> = []
        return symbols.filter { seen.insert($0.name).inserted }
    }

    private static func placeholder(
        documentSymbols: [JumpBarSymbol],
        syntaxSymbols: [EditorJumpBarSyntaxSymbol]
    ) -> JumpBarPathSegment {
        let roots = documentSymbols.filter { $0.parentID == nil && $0.isFunction }
        let items = roots.isEmpty ? syntaxRootFunctions(syntaxSymbols) : roots.map(item(for:))
        return JumpBarPathSegment(
            id: "no-selection",
            title: "No Selection",
            systemImage: "curlybraces",
            role: .placeholder,
            items: items
        )
    }

    private static func syntaxRootFunctions(_ symbols: [EditorJumpBarSyntaxSymbol]) -> [JumpBarPathSegment.Item] {
        symbols.filter { $0.kind == .function && $0.parentID == nil }.map { symbol in
            JumpBarPathSegment.Item(
                id: symbol.id,
                title: symbol.name,
                systemImage: symbol.systemImage,
                line: symbol.nameLine,
                column: symbol.nameColumn
            )
        }
    }
}
