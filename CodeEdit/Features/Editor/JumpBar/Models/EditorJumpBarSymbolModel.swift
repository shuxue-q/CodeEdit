//
//  EditorJumpBarSymbolModel.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/17/26.
//

import Foundation
import Combine
import LanguageServerProtocol
import CodeEditSourceEditor

/// A flattened document symbol shown as the last jump-bar crumb.
struct JumpBarSymbol: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: SymbolKind
    let range: LSPRange
    let selectionRange: LSPRange
    let depth: Int

    /// 1-indexed line of the symbol's selectable name.
    var line: Int { selectionRange.start.line + 1 }
    /// 1-indexed column of the symbol's selectable name.
    var column: Int { selectionRange.start.character + 1 }

    /// Whether a 1-indexed editor cursor sits inside this symbol's full range.
    func contains(line: Int, column: Int) -> Bool {
        let position = Position(line: max(line - 1, 0), character: max(column - 1, 0))
        if position < range.start { return false }
        if position > range.end { return false }
        return true
    }
}

/// Loads `textDocument/documentSymbol` and tracks the symbol enclosing the cursor.
@MainActor
final class EditorJumpBarSymbolModel: ObservableObject {
    @Published private(set) var symbols: [JumpBarSymbol] = []
    @Published private(set) var enclosingSymbol: JumpBarSymbol?

    @Service private var lspService: LSPService

    private var currentURI: String?
    private var currentURL: URL?
    private var lastCursor: CursorPosition?
    private var loadGeneration = 0

    /// Reloads symbols for `file`. Passing `nil` clears the crumb.
    func load(file: CEWorkspaceFile?) {
        loadGeneration += 1
        let generation = loadGeneration
        currentURL = file?.url
        currentURI = file?.url.lspURI
        enclosingSymbol = nil
        guard let file else {
            symbols = []
            return
        }
        let uri = file.url.lspURI
        Task { [weak self] in
            await self?.refresh(uri: uri, url: file.url, generation: generation)
        }
    }

    /// Recomputes the enclosing symbol from an already-loaded tree.
    func cursorMoved(_ position: CursorPosition?) {
        lastCursor = position
        enclosingSymbol = Self.enclosing(in: symbols, cursor: position)
    }

    /// Flattens a document-symbol response into preorder crumbs (parents before children).
    static func flatten(_ response: DocumentSymbolResponse) -> [JumpBarSymbol] {
        guard let response else { return [] }
        switch response {
        case .optionA(let documentSymbols):
            return flatten(documentSymbols, depth: 0)
        case .optionB(let information):
            return information.enumerated().map { index, info in
                JumpBarSymbol(
                    id: "\(info.location.uri):\(info.location.range.start.line):\(index)",
                    name: info.name,
                    kind: info.kind,
                    range: info.location.range,
                    selectionRange: info.location.range,
                    depth: 0
                )
            }
        }
    }

    /// The innermost flattened symbol containing `cursor`, or `nil`.
    static func enclosing(in symbols: [JumpBarSymbol], cursor: CursorPosition?) -> JumpBarSymbol? {
        guard let cursor else { return nil }
        let line = cursor.start.line
        let column = cursor.start.column
        return symbols.last { $0.contains(line: line, column: column) }
    }

    private static func flatten(_ symbols: [DocumentSymbol], depth: Int) -> [JumpBarSymbol] {
        var result: [JumpBarSymbol] = []
        for (index, symbol) in symbols.enumerated() {
            result.append(
                JumpBarSymbol(
                    id: "\(depth):\(index):\(symbol.name):\(symbol.range.start.line)",
                    name: symbol.name,
                    kind: symbol.kind,
                    range: symbol.range,
                    selectionRange: symbol.selectionRange,
                    depth: depth
                )
            )
            if let children = symbol.children, !children.isEmpty {
                result.append(contentsOf: flatten(children, depth: depth + 1))
            }
        }
        return result
    }

    private func refresh(uri: String, url: URL, generation: Int) async {
        guard let client = lspService.languageClient(forDocument: url) else {
            guard generation == loadGeneration else { return }
            symbols = []
            enclosingSymbol = nil
            return
        }
        do {
            let response = try await client.requestSymbols(for: uri)
            guard generation == loadGeneration else { return }
            symbols = Self.flatten(response)
            enclosingSymbol = Self.enclosing(in: symbols, cursor: lastCursor)
        } catch {
            guard generation == loadGeneration else { return }
            symbols = []
            enclosingSymbol = nil
        }
    }
}
