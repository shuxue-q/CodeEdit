//
//  ChainScratchServer.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation
import LanguageServerProtocol

/// What chain completion needs from a language server: a scratch copy of the document that it can edit
/// freely, so asking what follows `car.` never touches the user's buffer or the server's copy of it.
@MainActor
protocol ChainScratchServer: AnyObject {
    /// Makes the scratch document's content `text`, opening it on first use.
    func updateScratch(text: String) async throws
    /// The completion items, with the server's scores, at a position of the scratch document.
    func completeInScratch(at position: Position) async throws -> ScoredCompletionResponse
    /// Closes the scratch document.
    func closeScratch() async
}

/// A scratch document on a real language server: a sibling of the edited file that exists only in the
/// server's memory.
///
/// The document stays open between requests. Opening one costs a preamble build (about 200 ms for a
/// file including a few standard headers, more for heavy translation units); after that, replacing its
/// text and asking for completions takes a few milliseconds, because the preamble is reused.
@MainActor
final class LSPChainScratchServer: ChainScratchServer {
    /// The start of every scratch file name, so other parts of the app can recognize them.
    nonisolated static let namePrefix = "codeedit-chain-scratch-"

    /// The language server client this scratch document lives on.
    let client: LSPService.LanguageServerType
    private let uri: String
    private let languageId: String
    private var version = 0
    private var isOpen = false

    /// Creates a scratch document next to the document at `documentURI`, with the same extension so the
    /// server compiles it with the same flags.
    init?(client: LSPService.LanguageServerType, documentURI: String, languageId: String) {
        guard let documentURL = URL(string: documentURI) else { return nil }
        let name = Self.namePrefix + UUID().uuidString.prefix(8).lowercased()
        let sibling = documentURL.deletingLastPathComponent()
            .appendingPathComponent(name)
            .appendingPathExtension(documentURL.pathExtension)
        self.client = client
        self.uri = sibling.absoluteString
        self.languageId = languageId
    }

    /// Whether `uri` is the URI of a scratch document, whose diagnostics must not reach the problems panel.
    nonisolated static func isScratchURI(_ uri: String) -> Bool {
        uri.contains("/" + namePrefix)
    }

    deinit {
        // The scratch document must not outlive its owner on the server.
        guard isOpen else { return }
        let client = self.client
        let identifier = TextDocumentIdentifier(uri: uri)
        Task {
            try? await client.lspInstance.textDocumentDidClose(DidCloseTextDocumentParams(textDocument: identifier))
        }
    }

    func updateScratch(text: String) async throws {
        if isOpen {
            version += 1
            let change = TextDocumentContentChangeEvent(range: nil, rangeLength: nil, text: text)
            try await client.lspInstance.textDocumentDidChange(
                DidChangeTextDocumentParams(uri: uri, version: version, contentChange: change)
            )
        } else {
            version = 0
            let item = TextDocumentItem(uri: uri, languageId: languageId, version: 0, text: text)
            try await client.lspInstance.textDocumentDidOpen(DidOpenTextDocumentParams(textDocument: item))
            isOpen = true
        }
    }

    func completeInScratch(at position: Position) async throws -> ScoredCompletionResponse {
        try await client.requestScoredCompletion(for: uri, position: position)
    }

    func closeScratch() async {
        guard isOpen else { return }
        isOpen = false
        try? await client.lspInstance.textDocumentDidClose(
            DidCloseTextDocumentParams(textDocument: TextDocumentIdentifier(uri: uri))
        )
    }
}
