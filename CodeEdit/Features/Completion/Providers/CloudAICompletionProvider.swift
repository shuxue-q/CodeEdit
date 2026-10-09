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
/// Uses raw `URLSession` HTTP. The provider owns cancellation, the deadline, the minimum prefix rule,
/// error-log throttling and back-off; the backend owns the wire format.
/// A new request cancels the previous in-flight one; a short (<2 character) prefix skips the request
/// unless it was explicit.
///
/// After a failure that retrying right away cannot fix, the provider stops sending requests for a while
/// instead of failing on every keystroke: 30 seconds after a rate limit or server error (HTTP 429, 529,
/// 5xx), 5 minutes after the key was rejected (401, 403), 60 seconds when the network is unreachable.
/// The next trigger after the window sends a request again. Changing the provider, model, base URL or key
/// ends the back-off at once.
@MainActor
final class CloudAICompletionProvider: AICompletionProvider {
    /// The minimum typed-prefix length before an automatic (non-explicit) request is made.
    nonisolated static let minimumAutomaticPrefixLength = 2
    /// The minimum time between logged network/HTTP failures.
    static let errorLogInterval: TimeInterval = 60
    /// How long to stay quiet after a rate limit or a server error (HTTP 429, 529, 5xx).
    static let transientBackoff: Duration = .seconds(30)
    /// How long to stay quiet after the server rejected the key (HTTP 401, 403).
    static let authenticationBackoff: Duration = .seconds(300)
    /// How long to stay quiet after the network turned out to be unreachable.
    static let networkBackoff: Duration = .seconds(60)
    /// How long a request waits for the semantic facts (expected type, function header) before it is sent
    /// without them. They are usually ready already: they are resolved alongside the other providers.
    static let semanticsBudget: Duration = .milliseconds(200)

    let source: CompletionSource = .ai
    let deadline: Duration = .milliseconds(2_500)

    private let session: URLSession
    private let keychain: CodeEditKeychain
    private let settingsProvider: () -> SettingsData.TextEditingSettings.AICompletionSettings
    private let metrics: any CompletionMetricsRecording
    private let now: () -> ContinuousClock.Instant
    private var currentTask: Task<[CompletionCandidate], Never>?
    private var backoff: Backoff?
    private static var lastErrorLogDate: Date?
    private static let logger = Logger(subsystem: "app.codeedit.CodeEdit", category: "CloudAICompletionProvider")

    /// A pause in sending requests, for the configuration that caused it.
    private struct Backoff {
        let until: ContinuousClock.Instant
        let kind: AIBackendKind
        let configuration: AIBackendConfiguration
    }

    /// Creates a provider.
    /// - Parameters:
    ///   - session: The session used for requests. Injectable so tests can stub network calls.
    ///   - keychain: Where the API key is read from.
    ///   - settingsProvider: Returns the current AI completion settings.
    ///   - metrics: Where the backend's response times are recorded.
    ///   - now: The clock back-off is measured with. Injectable so tests need not wait.
    init(
        session: URLSession = .shared,
        keychain: CodeEditKeychain = CodeEditKeychain(),
        settingsProvider: @escaping () -> SettingsData.TextEditingSettings.AICompletionSettings = {
            Settings[\.textEditing].aiCompletion
        },
        metrics: any CompletionMetricsRecording = CompletionMetricsStore.shared,
        now: @escaping () -> ContinuousClock.Instant = { .now }
    ) {
        self.session = session
        self.keychain = keychain
        self.settingsProvider = settingsProvider
        self.metrics = metrics
        self.now = now
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
        guard !isBackedOff(kind: settings.backend, configuration: configuration) else { return [] }

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

        let clock = ContinuousClock()
        let start = clock.now
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard !Task.isCancelled else { return [] }
            metrics.recordBackendLatency(name: "ai.\(backend.kind.rawValue)", duration: clock.now - start)
            guard let httpResponse = response as? HTTPURLResponse else { return [] }
            guard (200..<300).contains(httpResponse.statusCode) else {
                handleFailure(status: httpResponse.statusCode, backend: backend, configuration: configuration)
                return []
            }
            return Self.candidates(from: data, response: httpResponse, backend: backend)
        } catch is CancellationError {
            return []
        } catch let error as URLError where error.code == .cancelled {
            return []
        } catch {
            if let error = error as? URLError, Self.isUnreachable(error) {
                startBackoff(Self.networkBackoff, backend: backend, configuration: configuration)
            }
            logError("\(backend.displayName) completion request failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Back-off

    /// How long to stay quiet after an HTTP error, or `nil` when retrying on the next trigger is fine.
    nonisolated static func backoffDuration(forStatus status: Int) -> Duration? {
        switch status {
        case 401, 403: return authenticationBackoff
        case 429, 529, 500...599: return transientBackoff
        default: return nil
        }
    }

    /// Whether `error` means the server could not be reached at all.
    nonisolated static func isUnreachable(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
             .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff, .timedOut:
            return true
        default:
            return false
        }
    }

    private func isBackedOff(kind: AIBackendKind, configuration: AIBackendConfiguration) -> Bool {
        guard let backoff else { return false }
        guard backoff.kind == kind, backoff.configuration == configuration else {
            self.backoff = nil
            return false
        }
        return now() < backoff.until
    }

    private func startBackoff(
        _ duration: Duration,
        backend: any AICompletionBackend,
        configuration: AIBackendConfiguration
    ) {
        backoff = Backoff(until: now().advanced(by: duration), kind: backend.kind, configuration: configuration)
    }

    private func handleFailure(
        status: Int,
        backend: any AICompletionBackend,
        configuration: AIBackendConfiguration
    ) {
        guard let duration = Self.backoffDuration(forStatus: status) else {
            logError("\(backend.displayName) completion request failed with HTTP \(status)")
            return
        }
        startBackoff(duration, backend: backend, configuration: configuration)
        if duration == Self.authenticationBackoff {
            Self.logger.error(
                "\(backend.displayName) rejected the API key (HTTP \(status)); AI completion is paused for 5 minutes"
            )
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
