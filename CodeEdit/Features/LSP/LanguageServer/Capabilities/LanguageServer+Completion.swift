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

    /// Requests completion items together with the relevance `score` clangd attaches to each of them.
    ///
    /// `LanguageServerProtocol.CompletionItem` has no `score` field, so the generic response type is
    /// replaced by ``ScoredCompletionResponse``, which decodes the same JSON and also keeps the score.
    /// Servers that send no score yield `nil` scores. This always bypasses the response cache.
    func requestScoredCompletion(
        for documentURI: String,
        position: Position
    ) async throws -> ScoredCompletionResponse {
        do {
            let params = CompletionParams(
                uri: documentURI,
                position: position,
                triggerKind: .invoked,
                triggerCharacter: nil
            )
            return try await lspInstance.sendRequest(.completion(params, ClientRequest.NullHandler))
        } catch {
            logger.warning("requestScoredCompletion: Error \(error)")
            throw error
        }
    }

    /// Whether the server advertised `workspace/symbol` support during initialization.
    var supportsWorkspaceSymbols: Bool {
        switch serverCapabilities.workspaceSymbolProvider {
        case .optionA(let supported):
            return supported
        case .optionB:
            return true
        case .none:
            return false
        }
    }

    /// Looks up symbols by name. Used when a completion item has no declaring header.
    ///
    /// Returns `nil` without contacting the server when it does not support `workspace/symbol`
    /// (for example `neocmakelsp`), which would otherwise answer with `-32601 Method not found`.
    func requestWorkspaceSymbols(query: String) async throws -> WorkspaceSymbolResponse {
        guard supportsWorkspaceSymbols else { return nil }
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

/// A `textDocument/completion` answer whose items keep the non-standard `score` clangd sends with them.
///
/// Decodes both response shapes (a bare array, or a list object with `items`) and `null`. It also keeps
/// what `LanguageServerProtocol.CompletionList` and `CompletionItem` drop: the list's `isIncomplete`
/// flag and each item's `labelDetails`.
struct ScoredCompletionResponse: Decodable, Sendable {
    /// The completion items, in the order the server sent them.
    var items: [CompletionItem] = []
    /// `scores[i]` is the server's `score` for `items[i]`, or `nil` when the server sent none.
    var scores: [Double?] = []
    /// `labelDetails[i]` is the `labelDetails` of `items[i]`, or `nil` when the server sent none.
    var labelDetails: [CompletionLabelDetails?] = []
    /// Whether the server said typing more should ask it again rather than filter this list. A bare
    /// array is complete.
    var isIncomplete = false

    private struct ScoredItem: Decodable {
        let item: CompletionItem
        let score: Double?
        let labelDetails: CompletionLabelDetails?

        private enum CodingKeys: String, CodingKey {
            case score
            case labelDetails
        }

        init(from decoder: Decoder) throws {
            item = try CompletionItem(from: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            score = try container.decodeIfPresent(Double.self, forKey: .score)
            labelDetails = try? container.decodeIfPresent(CompletionLabelDetails.self, forKey: .labelDetails)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case items
        case isIncomplete
    }

    init() {}

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() { return }
        let scored: [ScoredItem]
        if let array = try? single.decode([ScoredItem].self) {
            scored = array
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            scored = try container.decode([ScoredItem].self, forKey: .items)
            isIncomplete = try container.decodeIfPresent(Bool.self, forKey: .isIncomplete) ?? false
        }
        items = scored.map(\.item)
        scores = scored.map(\.score)
        labelDetails = scored.map(\.labelDetails)
    }
}

/// The LSP 3.17 `CompletionItemLabelDetails` of an item: text shown after its label.
///
/// The Dart analysis server puts the signature in `detail` (`(int length) → Uint8List`) and the library
/// that declares a not-yet-imported symbol in `description` (`dart:typed_data`).
struct CompletionLabelDetails: Decodable, Sendable, Equatable {
    /// Shown right after the label, without spacing: usually a signature.
    var detail: String?
    /// Shown after `detail`, less prominently: usually a qualified name or a file path.
    var description: String?

    /// `detail` and `description` as one line, or `nil` when both are empty.
    var displayText: String? {
        let parts = [detail, description]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "  ")
    }
}
