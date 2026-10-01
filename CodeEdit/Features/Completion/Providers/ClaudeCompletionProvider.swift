//
//  ClaudeCompletionProvider.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import CodeEditSourceEditor
import Foundation
import os

/// Requests AI-generated completions from the Claude API.
///
/// Opt-in: only makes requests when `Settings[\.textEditing].aiCompletion.enabled` is `true` and an
/// API key is present in the Keychain. Uses raw `URLSession` HTTP, since there is no official
/// Anthropic Swift SDK. A new request cancels the previous in-flight one; a short (<2 character)
/// prefix skips the request unless it was explicit.
@MainActor
final class ClaudeCompletionProvider: AICompletionProvider {
    /// The Anthropic Messages API endpoint.
    nonisolated static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    /// The minimum typed-prefix length before an automatic (non-explicit) request is made.
    nonisolated static let minimumAutomaticPrefixLength = 2
    /// How much of the document before the cursor is sent, in characters.
    nonisolated static let maxPrefixContextLength = 4_000
    /// How much of the document after the cursor is sent, in characters.
    nonisolated static let maxSuffixContextLength = 1_000
    /// The most suggestions requested per completion.
    nonisolated static let maxSuggestions = 3
    /// The minimum time between logged network/HTTP failures.
    static let errorLogInterval: TimeInterval = 60

    let source: CompletionSource = .ai
    let deadline: Duration = .milliseconds(2_500)

    private let session: URLSession
    private let keychain: CodeEditKeychain
    private let settingsProvider: () -> SettingsData.TextEditingSettings.AICompletionSettings
    private var currentTask: Task<[CompletionCandidate], Never>?
    private static var lastErrorLogDate: Date?

    /// Creates a provider.
    /// - Parameters:
    ///   - session: The session used for requests. Injectable so tests can stub network calls.
    ///   - keychain: Where the API key is read from.
    ///   - settingsProvider: Returns the current AI completion settings.
    init(
        session: URLSession = .shared,
        keychain: CodeEditKeychain = CodeEditKeychain(),
        settingsProvider: @escaping () -> SettingsData.TextEditingSettings.AICompletionSettings = {
            Settings[\.textEditing].aiCompletion
        }
    ) {
        self.session = session
        self.keychain = keychain
        self.settingsProvider = settingsProvider
    }

    func triggerCharacters() -> Set<String> { [] }

    func candidates(for context: CompletionContext, textView: TextViewController) async -> [CompletionCandidate] {
        let settings = settingsProvider()
        guard settings.enabled,
              let apiKey = keychain.get(SettingsData.TextEditingSettings.AICompletionSettings.keychainKey),
              !apiKey.isEmpty else {
            return []
        }
        guard context.isExplicit || context.prefix.count >= Self.minimumAutomaticPrefixLength else {
            return []
        }

        currentTask?.cancel()
        let task = Task { [weak self] () -> [CompletionCandidate] in
            guard let self else { return [] }
            return await self.performRequest(context: context, model: settings.model, apiKey: apiKey)
        }
        currentTask = task
        return await task.value
    }

    func apply(_ candidate: CompletionCandidate, textView: TextViewController, cursorPosition: CursorPosition?) {
        guard case .plain(let insertText) = candidate.payload,
              let cursorPosition,
              let resolved = textView.resolveCursorPosition(cursorPosition) else {
            return
        }
        let location = resolved.range.location
        let string = textView.textView.textStorage.string as NSString
        var wordStart = location
        let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$#"))
        while wordStart > 0,
              let scalar = Unicode.Scalar(string.character(at: wordStart - 1)),
              wordCharacters.contains(scalar) {
            wordStart -= 1
        }
        let replaceRange = NSRange(location: wordStart, length: location - wordStart)
        textView.textView.replaceCharacters(in: replaceRange, with: insertText)
    }

    // MARK: - Networking

    private func performRequest(
        context: CompletionContext,
        model: String,
        apiKey: String
    ) async -> [CompletionCandidate] {
        guard !Task.isCancelled else { return [] }
        let request = Self.makeRequest(context: context, model: model, apiKey: apiKey)
        do {
            let (data, response) = try await session.data(for: request)
            guard !Task.isCancelled else { return [] }
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                logError("Claude completion request failed with a non-2xx response")
                return []
            }
            return Self.candidates(from: data)
        } catch is CancellationError {
            return []
        } catch {
            logError("Claude completion request failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Builds the `POST /v1/messages` request body described by the completion aggregator design doc.
    nonisolated static func makeRequest(context: CompletionContext, model: String, apiKey: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody(context: context, model: model))
        return request
    }

    nonisolated static func requestBody(context: CompletionContext, model: String) -> [String: Any] {
        let (before, after) = splitContext(context)
        let userMessage = """
        Language: \(context.languageId)
        The user is typing \(context.intent.promptDescription).
        Code before the cursor:
        \(before)<cursor/>\(after)
        """
        return [
            "model": model,
            "max_tokens": 1_024,
            "fallbacks": "default",
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
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

    /// Splits `context.documentText` around `context.cursorOffset` (a UTF-16, `NSString`-style
    /// offset, matching every other cursor offset in this feature).
    nonisolated private static func splitContext(_ context: CompletionContext) -> (before: String, after: String) {
        let text = context.documentText as NSString
        let offset = max(0, min(context.cursorOffset, text.length))
        let before = text.substring(to: offset)
        let after = text.substring(from: offset)
        return (String(before.suffix(maxPrefixContextLength)), String(after.prefix(maxSuffixContextLength)))
    }

    nonisolated private static let systemPrompt = """
    You complete source code. Given the code immediately before and after a <cursor/> marker, \
    suggest up to 3 short completions that could be inserted at the cursor. Each suggestion is a \
    short label and the exact text to insert. Do not repeat code that is already present. If \
    nothing reasonable can be suggested, return an empty list.
    """

    nonisolated private static let completionSchema: [String: Any] = [
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
    /// A `refusal` (or any non-`end_turn` stop) yields no candidates. The structured output is the
    /// JSON text of the first `text` content block.
    nonisolated static func candidates(from data: Data) -> [CompletionCandidate] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        guard let stopReason = json["stop_reason"] as? String, stopReason == "end_turn" else { return [] }
        guard let content = json["content"] as? [[String: Any]] else { return [] }
        guard let textBlock = content.first(where: { ($0["type"] as? String) == "text" }),
              let text = textBlock["text"] as? String,
              let textData = text.data(using: .utf8) else {
            return []
        }
        guard let output = try? JSONDecoder().decode(StructuredOutput.self, from: textData) else { return [] }
        return output.completions.prefix(maxSuggestions).map { suggestion in
            CompletionCandidate(
                id: "ai.\(UUID().uuidString)",
                label: suggestion.label,
                filterText: suggestion.label,
                sortText: nil,
                kind: .snippet,
                source: .ai,
                detail: nil,
                documentation: nil,
                payload: .plain(insertText: suggestion.insertText)
            )
        }
    }

    private func logError(_ message: String) {
        let now = Date()
        if let last = Self.lastErrorLogDate, now.timeIntervalSince(last) < Self.errorLogInterval {
            return
        }
        Self.lastErrorLogDate = now
        Logger(subsystem: "app.codeedit.CodeEdit", category: "ClaudeCompletionProvider").error("\(message)")
    }
}
