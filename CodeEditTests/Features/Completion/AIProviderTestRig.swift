//
//  AIProviderTestRig.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import CodeEditLanguages
@testable import CodeEditSourceEditor
import Foundation

@testable import CodeEdit

/// An editor for provider tests; the AI provider only needs one to be handed to it.
@MainActor
func makeAITestEditor() -> TextViewController {
    let editor = TextViewController(
        string: "int main() {\n    \n}\n",
        language: .c,
        configuration: .init(appearance: .init(
            theme: ThemeModel.shared.themes[0].editor.editorTheme,
            font: .monospacedSystemFont(ofSize: 13, weight: .regular),
            wrapLines: false
        )),
        cursorPositions: [],
        highlightProviders: [],
        coordinators: []
    )
    editor.loadView()
    return editor
}

/// The completion context of a half-typed `pri` in a C function.
func makeAITestContext() -> CompletionContext {
    CompletionContext(
        prefix: "pri",
        prefixRange: NSRange(location: 0, length: 3),
        triggerCharacter: nil,
        intent: .statement,
        languageId: "c",
        documentText: "int main() {\n    pri\n}\n",
        cursorOffset: 20
    )
}

/// A metrics recorder that keeps what it is told.
@MainActor
final class AISpyMetrics: CompletionMetricsRecording {
    var backendLatencies: [String] = []
    func recordPopup() { }
    func recordProviderLatency(source: CompletionSource, duration: Duration) { }
    func recordBackendLatency(name: String, duration: Duration) { backendLatencies.append(name) }
    func recordAcceptance(rank: Int, keystrokes: Int) { }
}

/// A request counter the stub network can bump from its own thread.
final class AIRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

/// A provider wired to the stub network, a settable clock, a back-off store of its own and a spy for metrics.
@MainActor
final class AIProviderRig {
    typealias AISettings = SettingsData.TextEditingSettings.AICompletionSettings

    var settings = AISettings()
    var offset: Duration = .zero
    private let counter = AIRequestCounter()
    var requestCount: Int { counter.value }
    let metrics = AISpyMetrics()
    let keychain = CodeEditKeychain(keyPrefix: "test.\(UUID().uuidString).")
    let start = ContinuousClock.now
    let store = AICompletionBackoffStore()
    lazy var provider: CloudAICompletionProvider = makeProvider()

    /// A provider that shares this rig's back-off store, clock, settings and network.
    func makeProvider() -> CloudAICompletionProvider {
        CloudAICompletionProvider(
            session: AIStubURLProtocol.makeSession(),
            keychain: keychain,
            settingsProvider: { [unowned self] in settings },
            metrics: metrics,
            now: { [unowned self] in start.advanced(by: offset) },
            backoffStore: store
        )
    }

    init(backend: AIBackendKind = .anthropic) {
        settings.enabled = true
        settings.backend = backend
        keychain.set("key", forKey: AISettings.keychainKey(for: backend))
    }

    /// Answers every request with `status` and `body`, counting them.
    func respond(status: Int, body: String = "{}") {
        let counter = self.counter
        AIStubURLProtocol.handler = { request in
            counter.increment()
            let url = request.url!
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
    }

    /// Fails every request with `error`, counting them.
    func fail(with error: URLError.Code) {
        let counter = self.counter
        AIStubURLProtocol.handler = { _ in
            counter.increment()
            throw URLError(error)
        }
    }

    /// A well-formed Anthropic answer with one suggestion, `x`.
    static let goodAnthropicBody: String = {
        let output = #"{"completions":[{"label":"x","insertText":"x"}]}"#
        let json: [String: Any] = ["stop_reason": "end_turn", "content": [["type": "text", "text": output]]]
        let data = try! JSONSerialization.data(withJSONObject: json) // swiftlint:disable:this force_try
        return String(bytes: data, encoding: .utf8) ?? ""
    }()
}
