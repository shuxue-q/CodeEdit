//
//  LanguageServer+SemanticTokens.swift
//  CodeEdit
//
//  Created by Abe Malla on 2/7/24.
//

import Foundation
import LanguageServerProtocol

extension LanguageServer {
    /// Whether the server advertised `textDocument/semanticTokens/full` support during initialization.
    var supportsSemanticTokens: Bool {
        semanticTokensFullOption != nil
    }

    /// Whether the server advertised `textDocument/semanticTokens/full/delta` support during initialization.
    var supportsSemanticTokenDeltas: Bool {
        if case .optionB(let full) = semanticTokensFullOption {
            return full.delta ?? false
        }
        return false
    }

    private var semanticTokensFullOption: SemanticTokensClientCapabilities.Requests.FullOption? {
        let full: SemanticTokensClientCapabilities.Requests.FullOption?
        switch serverCapabilities.semanticTokensProvider {
        case .optionA(let options):
            full = options.full
        case .optionB(let options):
            full = options.full
        case .none:
            return nil
        }
        if case .optionA(false) = full {
            return nil
        }
        return full
    }

    /// Requests semantic tokens for an entire document.
    ///
    /// Returns `nil` without contacting the server when it does not support full-document semantic tokens.
    func requestSemanticTokens(for documentURI: String) async throws -> SemanticTokensResponse {
        guard supportsSemanticTokens else { return nil }
        do {
            let params = SemanticTokensParams(textDocument: TextDocumentIdentifier(uri: documentURI))
            return try await lspInstance.semanticTokensFull(params)
        } catch {
            logger.warning("requestSemanticTokens full: Error \(error)")
            throw error
        }
    }

    /// Requests a semantic token delta relative to `previousResultId`.
    ///
    /// Falls back to a full-document request when the server does not support deltas.
    func requestSemanticTokens(
        for documentURI: String,
        previousResultId: String
    ) async throws -> SemanticTokensDeltaResponse {
        guard supportsSemanticTokenDeltas else {
            return try await requestSemanticTokens(for: documentURI).map { .optionA($0) }
        }
        do {
            let params = SemanticTokensDeltaParams(
                textDocument: TextDocumentIdentifier(uri: documentURI),
                previousResultId: previousResultId
            )
            return try await lspInstance.semanticTokensFullDelta(params)
        } catch {
            logger.warning("requestSemanticTokens versioned: Error \(error)")
            throw error
        }
    }
}
