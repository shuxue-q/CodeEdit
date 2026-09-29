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

/// A flattened document symbol shown as one jump-bar crumb.
struct JumpBarSymbol: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: SymbolKind
    let detail: String?
    let range: LSPRange
    let selectionRange: LSPRange
    let depth: Int
    let parentID: String?

    /// 1-indexed line of the symbol's selectable name.
    var line: Int { selectionRange.start.line + 1 }
    /// 1-indexed column of the symbol's selectable name.
    var column: Int { selectionRange.start.character + 1 }

    /// Function crumbs keep a parameter list when the language server sends one.
    var pathTitle: String {
        guard isFunction else { return name }
        guard let detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty else {
            return name
        }
        if detail.hasPrefix(name) { return detail }
        if detail.hasPrefix("(") { return name + detail }
        return name
    }

    var isFunction: Bool {
        switch kind {
        case .function, .method, .constructor:
            return true
        default:
            return false
        }
    }

    var isVariable: Bool {
        switch kind {
        case .variable, .property, .field, .constant, .enumMember:
            return true
        default:
            return false
        }
    }

    /// Whether two symbols belong in the same sibling menu.
    func sharesMenu(with other: JumpBarSymbol) -> Bool {
        if isFunction && other.isFunction { return true }
        if isVariable && other.isVariable { return true }
        return kind == other.kind
    }

    var systemImage: String {
        if isFunction { return "f.square" }
        if isVariable { return "v.square" }
        switch kind {
        case .class, .interface:
            return "c.square"
        case .struct:
            return "s.square"
        case .enum:
            return "e.square"
        case .namespace, .module, .package:
            return "shippingbox"
        default:
            return "curlybraces"
        }
    }

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
    /// Crumbs after the file path: enclosing scopes, then the function, then the variable at the cursor.
    @Published private(set) var pathSegments: [JumpBarPathSegment] = []

    @Service private var lspService: LSPService

    private let syntaxIndex = EditorJumpBarSyntaxIndex()
    private var syntaxSubscription: AnyCancellable?
    private weak var syntaxDocument: CodeFileDocument?
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
        symbols = []
        enclosingSymbol = nil
        refreshPath()
        guard let file else { return }
        let uri = file.url.lspURI
        Task { [weak self] in
            await self?.refresh(uri: uri, url: file.url, generation: generation)
        }
    }

    /// Reparses declaration names used for the variable crumb. Safe to call on every edit.
    func observe(document: CodeFileDocument?) {
        syntaxSubscription?.cancel()
        syntaxDocument = document
        rebuildSyntax()
        guard let document else { return }
        syntaxSubscription = document.contentCoordinator.textUpdatePublisher
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.rebuildSyntax()
                }
            }
    }

    /// Recomputes the enclosing symbol from an already-loaded tree.
    func cursorMoved(_ position: CursorPosition?) {
        lastCursor = position
        refreshPath()
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
                    detail: nil,
                    range: info.location.range,
                    selectionRange: info.location.range,
                    depth: 0,
                    parentID: nil
                )
            }
        }
    }

    /// Symbols containing `cursor`, outermost first.
    static func enclosingChain(in symbols: [JumpBarSymbol], cursor: CursorPosition?) -> [JumpBarSymbol] {
        guard let cursor else { return [] }
        let line = cursor.start.line
        let column = cursor.start.column
        return symbols.filter { $0.contains(line: line, column: column) }
    }

    /// Symbols that share `symbol`'s parent. Root symbols are siblings of each other.
    static func siblings(of symbol: JumpBarSymbol, in symbols: [JumpBarSymbol]) -> [JumpBarSymbol] {
        symbols.filter { $0.parentID == symbol.parentID }
    }

    /// The innermost flattened symbol containing `cursor`, or `nil`.
    static func enclosing(in symbols: [JumpBarSymbol], cursor: CursorPosition?) -> JumpBarSymbol? {
        enclosingChain(in: symbols, cursor: cursor).last
    }

    private static func flatten(
        _ symbols: [DocumentSymbol],
        depth: Int,
        parentID: String? = nil
    ) -> [JumpBarSymbol] {
        var result: [JumpBarSymbol] = []
        for (index, symbol) in symbols.enumerated() {
            let id = "\(parentID ?? "root"):\(depth):\(index):\(symbol.name):\(symbol.range.start.line)"
            result.append(
                JumpBarSymbol(
                    id: id,
                    name: symbol.name,
                    kind: symbol.kind,
                    detail: symbol.detail,
                    range: symbol.range,
                    selectionRange: symbol.selectionRange,
                    depth: depth,
                    parentID: parentID
                )
            )
            if let children = symbol.children, !children.isEmpty {
                result.append(contentsOf: flatten(children, depth: depth + 1, parentID: id))
            }
        }
        return result
    }

    private func rebuildSyntax() {
        guard let document = syntaxDocument, let source = document.content?.string else {
            syntaxIndex.clear()
            refreshPath()
            return
        }
        syntaxIndex.rebuild(source: source, language: document.getLanguage())
        refreshPath()
    }

    private func refreshPath() {
        pathSegments = EditorJumpBarPath.segments(
            documentSymbols: symbols,
            syntaxSymbols: syntaxIndex.symbols,
            cursorVariable: syntaxIndex.variable(at: lastCursor),
            cursor: lastCursor
        )
        enclosingSymbol = Self.enclosing(in: symbols, cursor: lastCursor)
    }

    private func refresh(uri: String, url: URL, generation: Int) async {
        guard let client = lspService.languageClient(forDocument: url) else {
            guard generation == loadGeneration else { return }
            symbols = []
            refreshPath()
            return
        }
        do {
            let response = try await client.requestSymbols(for: uri)
            guard generation == loadGeneration else { return }
            symbols = Self.flatten(response)
            refreshPath()
        } catch {
            guard generation == loadGeneration else { return }
            symbols = []
            refreshPath()
        }
    }
}
