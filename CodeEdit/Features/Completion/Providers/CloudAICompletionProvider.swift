//
//  CloudAICompletionProvider.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import CodeEditSourceEditor
import Foundation
import os

/// Requests AI-generated completions from a cloud model through an ``AICompletionBackend``.
///
/// Opt-in: only makes requests when `Settings[\.textEditing].aiCompletion.enabled` is `true` and the
/// selected backend is configured (an API key in the Keychain, or a loopback server that needs none).
/// Uses raw `URLSession` HTTP. The provider owns cancellation, the deadline, the minimum prefix rule and
/// error-log throttling; the backend owns the wire format.
/// A new request cancels the previous in-flight one; a short (<2 character) prefix skips the request
/// unless it was explicit.
@MainActor
final class CloudAICompletionProvider: AICompletionProvider {
    /// The minimum typed-prefix length before an automatic (non-explicit) request is made.
    nonisolated static let minimumAutomaticPrefixLength = 2
    /// The minimum time between logged network/HTTP failures.
    static let errorLogInterval: TimeInterval = 60
    /// How long a request waits for the semantic facts (expected type, function header) before it is sent
    /// without them. They are usually ready already: they are resolved alongside the other providers.
    static let semanticsBudget: Duration = .milliseconds(200)

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
        guard settings.enabled else { return [] }
        guard context.isExplicit || context.prefix.count >= Self.minimumAutomaticPrefixLength else {
            return []
        }

        let keychainKey = SettingsData.TextEditingSettings.AICompletionSettings.keychainKey(for: settings.backend)
        let apiKey = keychain.get(keychainKey)
        let backend = settings.backend.backend
        let configuration = settings.configuration(apiKey: apiKey ?? "")

        currentTask?.cancel()
        let task = Task { [weak self] () -> [CompletionCandidate] in
            guard let self else { return [] }
            return await self.performRequest(context: context, backend: backend, configuration: configuration)
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
        backend: any AICompletionBackend,
        configuration: AIBackendConfiguration
    ) async -> [CompletionCandidate] {
        guard !Task.isCancelled else { return [] }
        do {
            let semantics = await context.awaitSemantics?(Self.semanticsBudget) ?? .none
            guard !Task.isCancelled else { return [] }
            let request = AICompletionPrompt.request(for: context, semantics: semantics)
            let urlRequest: URLRequest
            do {
                urlRequest = try backend.makeRequest(request, configuration: configuration)
            } catch {
                // Not configured (no key, no base URL): the normal state for a user who has not finished
                // setting AI up, so nothing is logged.
                return []
            }
            let (data, response) = try await session.data(for: urlRequest)
            guard !Task.isCancelled else { return [] }
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                logError("\(backend.displayName) completion request failed with a non-2xx response")
                return []
            }
            return Self.candidates(from: data, response: httpResponse, backend: backend)
        } catch is CancellationError {
            return []
        } catch {
            logError("\(backend.displayName) completion request failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Turns a backend's suggestions into completion candidates; a response the backend cannot read
    /// yields none.
    nonisolated static func candidates(
        from data: Data,
        response: HTTPURLResponse,
        backend: any AICompletionBackend
    ) -> [CompletionCandidate] {
        guard let suggestions = try? backend.suggestions(from: data, response: response) else { return [] }
        return suggestions.prefix(AICompletionPrompt.maxSuggestions).map { suggestion in
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
        Logger(subsystem: "app.codeedit.CodeEdit", category: "CloudAICompletionProvider").error("\(message)")
    }
}
