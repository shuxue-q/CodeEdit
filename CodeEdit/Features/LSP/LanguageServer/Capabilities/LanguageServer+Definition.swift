//
//  LanguageServer+Definition.swift
//  CodeEdit
//
//  Created by Abe Malla on 2/7/24.
//

import Foundation
import LanguageServerProtocol

extension LanguageServer {
    /// Requests the definition location of a symbol at a position in a document.
    /// - Parameters:
    ///   - documentURI: The URI of the document.
    ///   - position: The position of the symbol to resolve.
    ///   - bypassCache: Skips the response cache. The cache is keyed by URI and position only,
    ///     so it can serve stale results after edits. Interactive jumps should bypass it.
    func requestGoToDefinition(
        for documentURI: String,
        position: Position,
        bypassCache: Bool = false
    ) async throws -> DefinitionResponse {
        do {
            let cacheKey = CacheKey(
                uri: documentURI,
                requestType: "goToDefinition",
                extraData: position
            )
            if !bypassCache,
               let cachedResponse: DefinitionResponse = lspCache.get(key: cacheKey, as: DefinitionResponse.self) {
                return cachedResponse
            }

            let textDocumentIdentifier = TextDocumentIdentifier(uri: documentURI)
            let textDocumentPositionParams = TextDocumentPositionParams(
                textDocument: textDocumentIdentifier,
                position: position
            )
            let response = try await lspInstance.definition(textDocumentPositionParams)

            if !bypassCache {
                lspCache.set(key: cacheKey, value: response)
            }
            return response
        } catch {
            logger.warning("requestGoToDefinition: Error \(error)")
            throw error
        }
    }
}
