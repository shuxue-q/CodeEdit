//
//  AnthropicMessagesBackend.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// Talks to Anthropic's Messages API with structured output.
struct AnthropicMessagesBackend: AICompletionBackend {
    /// The Anthropic Messages API endpoint.
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    let kind: AIBackendKind = .anthropic
    let displayName = "Anthropic"

    func makeRequest(_ request: AICompletionRequest, configuration: AIBackendConfiguration) throws -> URLRequest {
        guard !configuration.apiKey.isEmpty else {
            throw AIBackendError.invalidConfiguration("An API key is required.")
        }
        var urlRequest = URLRequest(url: configuration.baseURL ?? Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        for (name, value) in configuration.extraHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        urlRequest.httpBody = try? JSONSerialization.data(
            withJSONObject: Self.requestBody(request: request, model: configuration.model)
        )
        return urlRequest
    }

    /// Builds the `POST /v1/messages` request body described by the completion aggregator design doc.
    static func requestBody(request: AICompletionRequest, model: String) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 1_024,
            "fallbacks": "default",
            "system": AICompletionPrompt.systemPrompt,
            "messages": [
                ["role": "user", "content": AICompletionPrompt.userMessage(for: request)]
            ],
            "output_config": [
                "effort": "low",
                "format": [
                    "type": "json_schema",
                    "schema": completionSchema
                ]
            ]
        ]
    }

    private static let completionSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "completions": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "label": ["type": "string"],
                        "insertText": ["type": "string"]
                    ],
                    "required": ["label", "insertText"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["completions"],
        "additionalProperties": false
    ]

    // MARK: - Response decoding

    /// One item in the model's `{completions: [{label, insertText}]}` structured output.
    struct Suggestion: Decodable, Equatable {
        let label: String
        let insertText: String
    }

    /// The decoded structured-output payload.
    struct StructuredOutput: Decodable, Equatable {
        let completions: [Suggestion]
    }

    /// Decodes the Messages API response, honoring `stop_reason` before reading `content`.
    ///
    /// A `refusal` (or any non-`end_turn` stop) yields no suggestions. The structured output is the
    /// JSON text of the first `text` content block.
    func suggestions(from data: Data, response: HTTPURLResponse) throws -> [AICompletionSuggestion] {
        guard (200..<300).contains(response.statusCode) else {
            throw AIBackendError.server(status: response.statusCode, message: Self.errorMessage(in: data))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIBackendError.malformedResponse
        }
        guard let stopReason = json["stop_reason"] as? String, stopReason == "end_turn" else { return [] }
        guard let content = json["content"] as? [[String: Any]] else { throw AIBackendError.malformedResponse }
        guard let textBlock = content.first(where: { ($0["type"] as? String) == "text" }),
              let text = textBlock["text"] as? String,
              let textData = text.data(using: .utf8) else {
            throw AIBackendError.malformedResponse
        }
        guard let output = try? JSONDecoder().decode(StructuredOutput.self, from: textData) else {
            throw AIBackendError.malformedResponse
        }
        return output.completions.map { AICompletionSuggestion(label: $0.label, insertText: $0.insertText) }
    }

    /// The `error.message` of an Anthropic error envelope, if the body is one.
    private static func errorMessage(in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else {
            return nil
        }
        return error["message"] as? String
    }
}
