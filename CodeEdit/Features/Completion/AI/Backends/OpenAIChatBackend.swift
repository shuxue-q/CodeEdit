//
//  OpenAIChatBackend.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// Talks to any server that implements the OpenAI Chat Completions API: OpenAI itself, DeepSeek, Moonshot,
/// Qwen (DashScope compatible mode), Ollama, LM Studio and others. Those differ only by base URL, model and
/// whether a key is required, so one implementation serves every ``AIBackendKind/openAI`` and
/// ``AIBackendKind/openAICompatible`` configuration.
struct OpenAIChatBackend: AICompletionBackend {
    /// The base URL used when the configuration has none.
    static let defaultBaseURL = URL(string: "https://api.openai.com/v1")!

    /// How a request names its token limit and whether it sets a temperature.
    ///
    /// OpenAI's current models reject `max_tokens` and any `temperature` but the default; older models and
    /// most compatible servers expect them.
    enum ParameterStyle: Equatable, Sendable {
        /// `max_completion_tokens`, and no `temperature`.
        case current
        /// `max_tokens` and `temperature: 0.2`.
        case legacy

        /// The other wording.
        var other: ParameterStyle { self == .current ? .legacy : .current }
    }

    let kind: AIBackendKind
    /// The wording of the token limit and temperature in the request body.
    let parameterStyle: ParameterStyle

    var displayName: String {
        kind == .openAI ? "OpenAI" : "OpenAI-compatible server"
    }

    /// Creates a backend. `kind` decides the display name, whether a base URL is mandatory and, unless
    /// `parameterStyle` is given, the wording of the body: ``ParameterStyle/current`` for OpenAI itself,
    /// ``ParameterStyle/legacy`` for compatible servers.
    init(kind: AIBackendKind = .openAI, parameterStyle: ParameterStyle? = nil) {
        self.kind = kind
        self.parameterStyle = parameterStyle ?? (kind == .openAI ? .current : .legacy)
    }

    func makeRequest(_ request: AICompletionRequest, configuration: AIBackendConfiguration) throws -> URLRequest {
        let baseURL: URL
        if let configured = configuration.baseURL {
            baseURL = configured
        } else if kind == .openAICompatible {
            throw AIBackendError.invalidConfiguration("A base URL is required.")
        } else {
            baseURL = Self.defaultBaseURL
        }
        guard !configuration.apiKey.isEmpty || Self.isLoopback(baseURL) else {
            throw AIBackendError.invalidConfiguration("An API key is required.")
        }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        if !configuration.apiKey.isEmpty {
            urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        }
        for (name, value) in configuration.extraHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        urlRequest.httpBody = try? JSONSerialization.data(
            withJSONObject: Self.requestBody(
                request: request, model: configuration.model, kind: kind, parameterStyle: parameterStyle
            )
        )
        return urlRequest
    }

    /// The most tokens a compatible server may generate.
    static let maxOutputTokens = 256

    /// The most tokens an OpenAI model may generate. OpenAI counts a reasoning model's hidden reasoning
    /// tokens against the limit, so 256 can be used up before any visible answer is written.
    static let openAIMaxOutputTokens = 1024

    /// The token limit a request to a backend of `kind` carries.
    static func tokenLimit(for kind: AIBackendKind) -> Int {
        kind == .openAI ? openAIMaxOutputTokens : maxOutputTokens
    }

    /// Builds the `POST {baseURL}/chat/completions` request body.
    static func requestBody(
        request: AICompletionRequest,
        model: String,
        kind: AIBackendKind,
        parameterStyle: ParameterStyle
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": AICompletionPrompt.userMessage(for: request)]
            ],
            "n": 1,
            "response_format": ["type": "json_object"]
        ]
        let tokenLimit = tokenLimit(for: kind)
        switch parameterStyle {
        case .current:
            body["max_completion_tokens"] = tokenLimit
        case .legacy:
            body["max_tokens"] = tokenLimit
            body["temperature"] = 0.2
        }
        return body
    }

    /// The names a server's 400 uses when it refuses a parameter of the body.
    private static let parameterRejectionMarkers = [
        "unsupported parameter", "unsupported_parameter", "unsupported_value", "unsupported value",
        "temperature", "max_tokens", "max_completion_tokens"
    ]

    func alternative(afterRejection data: Data, response: HTTPURLResponse) -> (any AICompletionBackend)? {
        guard response.statusCode == 400,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else {
            return nil
        }
        let described = ["message", "code", "param", "type"]
            .compactMap { error[$0] as? String }
            .joined(separator: " ")
            .lowercased()
        guard Self.parameterRejectionMarkers.contains(where: described.contains) else { return nil }
        return OpenAIChatBackend(kind: kind, parameterStyle: parameterStyle.other)
    }

    /// The shared system prompt plus the output format. OpenAI's JSON mode requires the word "JSON" in the
    /// messages.
    static let systemPrompt = AICompletionPrompt.systemPrompt + """


    Respond with a JSON object of the form {"completions": ["text to insert", "another text to insert"]}. \
    Each entry is the exact text to insert at the cursor. Use {"completions": []} when nothing fits.
    """

    // MARK: - Response decoding

    func suggestions(from data: Data, response: HTTPURLResponse) throws -> [AICompletionSuggestion] {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let error = json?["error"] as? [String: Any] {
            throw AIBackendError.server(status: response.statusCode, message: error["message"] as? String)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw AIBackendError.server(status: response.statusCode, message: nil)
        }
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = Self.text(of: message["content"]) else {
            throw AIBackendError.malformedResponse
        }
        return Self.suggestions(fromContent: content)
    }

    /// The message content as a string: either a plain string or an array of `{type: "text", text}` parts.
    private static func text(of content: Any?) -> String? {
        if let string = content as? String { return string }
        if let parts = content as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined()
        }
        return nil
    }

    /// Reads suggestions out of the model's reply: the requested `{"completions": [...]}` object first,
    /// then a fenced or bare JSON array, and finally one suggestion per non-empty line.
    static func suggestions(fromContent content: String) -> [AICompletionSuggestion] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let unfenced = stripFence(trimmed)
        for candidate in [trimmed, unfenced] {
            if let parsed = parseJSON(candidate) { return parsed }
        }
        return unfenced.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("```") }
            .map(suggestion(forText:))
    }

    private static func parseJSON(_ text: String) -> [AICompletionSuggestion]? {
        guard let data = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        let entries: [Any]
        if let object = value as? [String: Any], let completions = object["completions"] as? [Any] {
            entries = completions
        } else if let array = value as? [Any] {
            entries = array
        } else {
            return nil
        }
        return entries.compactMap { entry in
            if let string = entry as? String {
                return suggestion(forText: string)
            }
            if let object = entry as? [String: Any],
               let insertText = (object["insertText"] ?? object["text"]) as? String {
                let label = (object["label"] as? String) ?? firstLine(of: insertText)
                return insertText.isEmpty ? nil : AICompletionSuggestion(label: label, insertText: insertText)
            }
            return nil
        }
    }

    private static func suggestion(forText text: String) -> AICompletionSuggestion {
        AICompletionSuggestion(label: firstLine(of: text), insertText: text)
    }

    private static func firstLine(of text: String) -> String {
        text.split(whereSeparator: \.isNewline).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? text
    }

    /// Removes a surrounding Markdown code fence (` ```json ... ``` `), if there is one.
    private static func stripFence(_ text: String) -> String {
        guard text.hasPrefix("```") else { return text }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines.removeFirst()
        if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether `url` points at this machine, where a local server needs no API key.
    static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".localhost")
    }
}
