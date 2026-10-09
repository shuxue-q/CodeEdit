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
/// 5xx), 5 minutes after the key was rejected (401, 403), 2 minutes after the server refused the request
/// itself (400, 404, 422: a wrong model name or base URL), 60 seconds when the network is unreachable.
/// The next trigger after the window sends a request again. Changing the provider, model, base URL or key
/// ends the back-off at once, and so does a successful Test Connection in the settings.
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
    /// How long to stay quiet after the server refused the request itself (HTTP 400, 404, 422), which a wrong
    /// model name or base URL does on every request.
    static let configurationBackoff: Duration = .seconds(120)
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
    private let backoffStore: AICompletionBackoffStore
    private var rememberedWording: RememberedWording?
    private static var lastErrorLogDate: Date?
    private static let logger = Logger(subsystem: "app.codeedit.CodeEdit", category: "CloudAICompletionProvider")

    /// The backend wording a server accepted after it refused the first one, for the configuration it worked with.
    private struct RememberedWording {
        let kind: AIBackendKind
        let configuration: AIBackendConfiguration
        let backend: any AICompletionBackend
    }

    /// Creates a provider.
    /// - Parameters:
    ///   - session: The session used for requests. Injectable so tests can stub network calls.
    ///   - keychain: Where the API key is read from.
    ///   - settingsProvider: Returns the current AI completion settings.
    ///   - metrics: Where the backend's response times are recorded.
    ///   - now: The clock back-off is measured with. Injectable so tests need not wait.
    ///   - backoffStore: Where back-off is recorded. The default is private to this provider; the app passes
    ///     ``AICompletionBackoffStore/shared`` so that all documents and the settings page agree.
    init(
        session: URLSession = .shared,
        keychain: CodeEditKeychain = CodeEditKeychain(),
        settingsProvider: @escaping () -> SettingsData.TextEditingSettings.AICompletionSettings = {
            Settings[\.textEditing].aiCompletion
        },
        metrics: any CompletionMetricsRecording = CompletionMetricsStore.shared,
        now: @escaping () -> ContinuousClock.Instant = { .now },
        backoffStore: AICompletionBackoffStore = AICompletionBackoffStore()
    ) {
        self.session = session
        self.keychain = keychain
        self.settingsProvider = settingsProvider
        self.metrics = metrics
        self.now = now
        self.backoffStore = backoffStore
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
        let configuration = settings.configuration(apiKey: apiKey ?? "")
        let backend = acceptedBackend(kind: settings.backend, configuration: configuration)
        guard !backoffStore.isBackedOff(kind: settings.backend, configuration: configuration, now: now()) else {
            return []
        }

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
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let exchange = try await AICompletionTransport.send(
                request, backend: backend, configuration: configuration, session: session
            )
            guard !Task.isCancelled else { return [] }
            metrics.recordBackendLatency(name: "ai.\(backend.kind.rawValue)", duration: clock.now - start)
            return candidates(from: exchange, requested: backend, configuration: configuration)
        } catch AIBackendError.invalidConfiguration {
            // Not configured (no key, no base URL): the normal state for a user who has not finished
            // setting AI up, so nothing is logged.
            return []
        } catch AIBackendError.malformedResponse {
            return []
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

    /// The candidates in an answer, after noting what it says about the configuration: an error starts a
    /// back-off, and a wording the server accepted only after refusing the first one is remembered.
    private func candidates(
        from exchange: AICompletionExchange,
        requested backend: any AICompletionBackend,
        configuration: AIBackendConfiguration
    ) -> [CompletionCandidate] {
        guard (200..<300).contains(exchange.response.statusCode) else {
            handleFailure(exchange, configuration: configuration)
            return []
        }
        if exchange.usedAlternative {
            rememberedWording = RememberedWording(
                kind: backend.kind, configuration: configuration, backend: exchange.backend
            )
        }
        return Self.candidates(from: exchange.data, response: exchange.response, backend: exchange.backend)
    }

    // MARK: - Back-off

    /// How long to stay quiet after an HTTP error, or `nil` when retrying on the next trigger is fine.
    nonisolated static func backoffDuration(forStatus status: Int) -> Duration? {
        switch status {
        case 401, 403: return authenticationBackoff
        case 429, 529, 500...599: return transientBackoff
        case 400, 404, 422: return configurationBackoff
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

    /// The backend to send with: the wording a server accepted earlier for this configuration, if any.
    private func acceptedBackend(
        kind: AIBackendKind,
        configuration: AIBackendConfiguration
    ) -> any AICompletionBackend {
        if let rememberedWording {
            if rememberedWording.kind == kind, rememberedWording.configuration == configuration {
                return rememberedWording.backend
            }
            self.rememberedWording = nil
        }
        return kind.backend
    }

    private func startBackoff(
        _ duration: Duration,
        backend: any AICompletionBackend,
        configuration: AIBackendConfiguration
    ) {
        backoffStore.start(until: now().advanced(by: duration), kind: backend.kind, configuration: configuration)
    }

    private func handleFailure(_ exchange: AICompletionExchange, configuration: AIBackendConfiguration) {
        let status = exchange.response.statusCode
        let backend = exchange.backend
        guard let duration = Self.backoffDuration(forStatus: status) else {
            logError("\(backend.displayName) completion request failed with HTTP \(status)")
            return
        }
        startBackoff(duration, backend: backend, configuration: configuration)
        if duration == Self.authenticationBackoff {
            Self.logger.error(
                "\(backend.displayName) rejected the API key (HTTP \(status)); AI completion is paused for 5 minutes"
            )
        } else if duration == Self.configurationBackoff {
            // Logged once per back-off: nothing is sent, so nothing fails again until the pause is over.
            let message = Self.serverMessage(in: exchange) ?? "no message"
            Self.logger.error(
                """
                \(backend.kind.rawValue) (\(backend.displayName)) refused the request with HTTP \(status): \(message). \
                Check the model name and base URL; AI completion is paused for 2 minutes.
                """
            )
        }
    }

    /// The explanation the server gave with an error status, if it gave one.
    nonisolated private static func serverMessage(in exchange: AICompletionExchange) -> String? {
        do {
            _ = try exchange.backend.suggestions(from: exchange.data, response: exchange.response)
        } catch let AIBackendError.server(_, message) {
            return message
        } catch {
            return nil
        }
        return nil
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
