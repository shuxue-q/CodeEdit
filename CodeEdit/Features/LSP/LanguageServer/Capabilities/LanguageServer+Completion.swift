//
//  LanguageServer+Completion.swift
//  CodeEdit
//
//  Created by Abe Malla on 2/7/24.
//

import Foundation
import LanguageServerProtocol

extension LanguageServer {
    /// Requests completion items at a position in a document.
    /// - Parameters:
    ///   - documentURI: The URI of the document.
    ///   - position: The position to request completions for.
    ///   - bypassCache: Skips the response cache. The cache is keyed by URI and position only,
    ///     so it can serve stale or partial (server warm-up) results after edits. Interactive
    ///     completion should bypass it.
    func requestCompletion(
        for documentURI: String,
        position: Position,
        bypassCache: Bool = false
    ) async throws -> CompletionResponse {
        do {
            let cacheKey = CacheKey(
                uri: documentURI,
                requestType: "completion",
                extraData: position
            )
            if !bypassCache,
               let cachedResponse: CompletionResponse = lspCache.get(key: cacheKey, as: CompletionResponse.self) {
                return cachedResponse
            }
            let completionParams = CompletionParams(
                uri: documentURI,
                position: position,
                triggerKind: .invoked,
                triggerCharacter: nil
            )
            let response = try await lspInstance.completion(completionParams)

            if !bypassCache {
                lspCache.set(key: cacheKey, value: response)
            }
            return response
        } catch {
            logger.warning("requestCompletion: Error \(error)")
            throw error
        }
    }

    /// Looks up symbols by name. Used when a completion item has no declaring header.
    func requestWorkspaceSymbols(query: String) async throws -> WorkspaceSymbolResponse {
        do {
            return try await lspInstance.workspaceSymbol(WorkspaceSymbolParams(query: query))
        } catch {
            logger.warning("requestWorkspaceSymbols: Error \(error)")
            throw error
        }
    }

    /// Loads documentation and detail that the server left off the original completion item.
    func requestCompletionResolve(_ item: CompletionItem) async throws -> CompletionItem {
        do {
            return try await lspInstance.completeItemResolve(item)
        } catch {
            logger.warning("requestCompletionResolve: Error \(error)")
            throw error
        }
    }
}
