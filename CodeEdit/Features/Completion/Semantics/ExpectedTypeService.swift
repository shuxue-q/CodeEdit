//
//  ExpectedTypeService.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageServerProtocol
import SwiftTreeSitter

/// Connects ``ExpectedTypeResolver`` to a live document: tree-sitter for syntax, the language server
/// for the types of symbols and the active parameter.
///
/// Every request to the server is bounded by ``requestBudget`` with `awaitValue(of:upTo:)` and cached
/// per document content, so asking again while the user keeps typing costs nothing and a slow server
/// only costs the expected-type bonus, never the popup. A request that outlives its budget keeps
/// running and fills the cache for the next keystroke.
@MainActor
final class ExpectedTypeService {
    /// The longest a hover or signature help request holds the completion up.
    static let requestBudget: Duration = .milliseconds(200)

    /// What a cached answer is for: one request kind at one offset of one document content.
    private struct CacheKey: Hashable {
        enum Kind: Hashable { case hover, signature }
        let kind: Kind
        let offset: Int
        let length: Int
        let hash: Int
    }

    private weak var document: CodeFileDocument?
    private let treeSitterClient: TreeSitterClient
    private let clientProvider: () -> LSPService.LanguageServerType?
    private var cache: [CacheKey: TypeText?] = [:]
    private var inFlight: [CacheKey: Task<TypeText?, Never>] = [:]

    /// How many requests reached the language server, for tests of the cache.
    private(set) var requestCount = 0

    init(
        document: CodeFileDocument?,
        treeSitterClient: TreeSitterClient,
        clientProvider: @escaping () -> LSPService.LanguageServerType?
    ) {
        self.document = document
        self.treeSitterClient = treeSitterClient
        self.clientProvider = clientProvider
    }

    /// The type expected at the cursor of `context`, or `nil` if there is none or it is not known in time.
    func expectedType(for context: CompletionContext, textView: TextViewController) async -> TypeText? {
        guard ExpectedTypeResolver.intents.contains(context.intent) else { return nil }
        let environment = ExpectedTypeEnvironment(
            nodeTypesAt: { [treeSitterClient] in CompletionIntentRecognizer.nodeTypes(at: $0, in: treeSitterClient) },
            fieldRange: { [treeSitterClient] location, type, field in
                Self.fieldRange(of: field, inAncestor: type, at: location, in: treeSitterClient)
            },
            typeOfSymbol: { [weak self, weak textView] offset in
                guard let self, let textView else { return nil }
                return await self.cachedRequest(.hover, offset: offset, context: context) { client, uri, position in
                    guard let hover = try await client.requestHover(for: uri, position) else { return nil }
                    return LSPTypeExtraction.type(fromHover: LSPTypeExtraction.text(of: hover))
                } position: {
                    textView.textView.lspPositionFrom(offset: offset)
                }
            },
            activeParameterType: { [weak self, weak textView] offset in
                guard let self, let textView else { return nil }
                return await self.cachedRequest(.signature, offset: offset, context: context) { client, uri, position in
                    guard let help = try await client.requestSignatureHelp(for: uri, position) else { return nil }
                    return LSPTypeExtraction.activeParameterType(in: help)
                } position: {
                    textView.textView.lspPositionFrom(offset: offset)
                }
            }
        )
        let resolver = ExpectedTypeResolver(environment: environment)
        return await resolver.resolve(
            text: context.documentText,
            prefixStart: context.prefixRange.location,
            cursor: context.cursorOffset,
            intent: context.intent,
            languageId: context.languageId
        )
    }

    // MARK: - Language server requests

    /// Runs `request` against the language server at `position`, bounded by ``requestBudget``, and
    /// caches the answer for this document content.
    private func cachedRequest(
        _ kind: CacheKey.Kind,
        offset: Int,
        context: CompletionContext,
        request: @escaping (LSPService.LanguageServerType, String, Position) async throws -> TypeText?,
        position: () -> Position?
    ) async -> TypeText? {
        let key = CacheKey(
            kind: kind,
            offset: offset,
            length: context.documentText.utf8.count,
            hash: context.documentText.hashValue
        )
        if let cached = cache[key] { return cached }
        let task: Task<TypeText?, Never>
        if let running = inFlight[key] {
            task = running
        } else {
            guard let document,
                  let uri = document.languageServerURI,
                  let client = clientProvider(),
                  let position = position() else {
                return nil
            }
            requestCount += 1
            task = Task { @MainActor [weak self] in
                let result: TypeText?
                do {
                    try await document.languageServerObjects.textCoordinator.flushPendingChanges()
                    result = try await request(client, uri, position)
                } catch {
                    result = nil
                }
                self?.finish(key, result: result)
                return result
            }
            inFlight[key] = task
        }
        // `nil` on a timeout: skipped without penalty, and the cache fills when the server answers.
        return await awaitValue(of: task, upTo: Self.requestBudget) ?? nil
    }

    private func finish(_ key: CacheKey, result: TypeText?) {
        inFlight[key] = nil
        if cache.count > 64 { cache.removeAll() }
        cache[key] = .some(result)
    }

    // MARK: - Syntax tree

    /// The range of the `field` child of the innermost `ancestorType` node around `location`.
    private static func fieldRange(
        of field: String,
        inAncestor ancestorType: String,
        at location: Int,
        in client: TreeSitterClient
    ) -> NSRange? {
        guard let results = try? client.nodesAt(location: location) else { return nil }
        for result in results {
            var node: Node? = result.node
            while let current = node {
                if current.nodeType == ancestorType {
                    return current.child(byFieldName: field)?.range
                }
                node = current.parent
            }
        }
        return nil
    }
}
