//
//  AICompletionBackend.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// The wire protocol an AI completion backend speaks.
enum AIBackendKind: String, Codable, CaseIterable, Sendable {
    /// Anthropic's Messages API.
    case anthropic
    /// OpenAI's Chat Completions API.
    case openAI
    /// Any other server that speaks the OpenAI Chat Completions API, at a custom base URL.
    case openAICompatible
}

/// What a backend needs, besides the request, to reach its server.
struct AIBackendConfiguration: Sendable, Equatable {
    /// The model identifier.
    var model: String
    /// The server's base URL; `nil` uses the backend's own default.
    var baseURL: URL?
    /// The API key; empty when none is configured.
    var apiKey: String
    /// Headers added to every request.
    var extraHeaders: [String: String]

    /// Creates a configuration.
    init(model: String, baseURL: URL? = nil, apiKey: String, extraHeaders: [String: String] = [:]) {
        self.model = model
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.extraHeaders = extraHeaders
    }
}

/// Why a backend could not produce suggestions.
enum AIBackendError: Error, Equatable {
    /// The configuration cannot form a request (no usable base URL, or a key is required and missing).
    case invalidConfiguration(String)
    /// The server answered with an error; carries the HTTP status and the server's message, if any.
    case server(status: Int, message: String?)
    /// The response was not in the shape the backend expects.
    case malformedResponse
}

/// One vendor wire format for AI completion: how to ask, and how to read the answer. The provider owns
/// cancellation, deadlines and the network call; a backend is pure request building and response parsing.
protocol AICompletionBackend: Sendable {
    /// The protocol this backend speaks.
    var kind: AIBackendKind { get }
    /// A human-readable name for logs and the settings UI.
    var displayName: String { get }
    /// Builds the HTTP request for `request`.
    func makeRequest(_ request: AICompletionRequest, configuration: AIBackendConfiguration) throws -> URLRequest
    /// Reads the suggestions out of a response. Returns an empty list when the model declined or had
    /// nothing to suggest; throws when the response is an error or not in the expected shape.
    func suggestions(from data: Data, response: HTTPURLResponse) throws -> [AICompletionSuggestion]
}

extension AIBackendKind {
    /// The backend implementation for this kind.
    var backend: any AICompletionBackend {
        switch self {
        case .anthropic: return AnthropicMessagesBackend()
        // The OpenAI-compatible backend is added in the next step; until then these kinds are unreachable
        // because no setting selects them.
        case .openAI, .openAICompatible: return AnthropicMessagesBackend()
        }
    }
}
