//
//  CloudAICompletionProviderBackoffTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import CodeEditLanguages
@testable import CodeEditSourceEditor
import XCTest

@testable import CodeEdit

/// How the AI provider backs off after failures, and the latency it reports.
final class CloudAICompletionProviderBackoffTests: XCTestCase {
    private typealias AISettings = SettingsData.TextEditingSettings.AICompletionSettings

    @MainActor
    private func makeEditor() -> TextViewController {
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

    private func context() -> CompletionContext {
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
    private final class SpyMetrics: CompletionMetricsRecording {
        var backendLatencies: [String] = []
        func recordPopup() { }
        func recordProviderLatency(source: CompletionSource, duration: Duration) { }
        func recordBackendLatency(name: String, duration: Duration) { backendLatencies.append(name) }
        func recordAcceptance(rank: Int, keystrokes: Int) { }
    }

    /// A request counter the stub network can bump from its own thread.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var value: Int { lock.withLock { count } }
        func increment() { lock.withLock { count += 1 } }
    }

    /// A provider wired to the stub network, a settable clock and a spy for metrics.
    @MainActor
    private final class Rig {
        var settings = AISettings()
        var offset: Duration = .zero
        private let counter = Counter()
        var requestCount: Int { counter.value }
        let metrics = SpyMetrics()
        let keychain = CodeEditKeychain(keyPrefix: "test.\(UUID().uuidString).")
        let start = ContinuousClock.now
        lazy var provider: CloudAICompletionProvider = CloudAICompletionProvider(
            session: AIStubURLProtocol.makeSession(),
            keychain: keychain,
            settingsProvider: { [unowned self] in settings },
            metrics: metrics,
            now: { [unowned self] in start.advanced(by: offset) }
        )

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
    }

    /// A well-formed Anthropic answer with one suggestion, `x`.
    private static let goodAnthropicBody: String = {
        let output = #"{"completions":[{"label":"x","insertText":"x"}]}"#
        let json: [String: Any] = ["stop_reason": "end_turn", "content": [["type": "text", "text": output]]]
        let data = try! JSONSerialization.data(withJSONObject: json) // swiftlint:disable:this force_try
        return String(bytes: data, encoding: .utf8) ?? ""
    }()

    @MainActor
    func testRateLimitBacksOffForThirtySecondsThenRetries() async {
        let rig = Rig()
        defer { AIStubURLProtocol.handler = nil }
        rig.respond(status: 429)
        let editor = makeEditor()
        _ = await rig.provider.candidates(for: context(), textView: editor)
        XCTAssertEqual(rig.requestCount, 1)

        _ = await rig.provider.candidates(for: context(), textView: editor)
        rig.offset = .seconds(29)
        _ = await rig.provider.candidates(for: context(), textView: editor)
        XCTAssertEqual(rig.requestCount, 1, "No request while backed off")

        rig.offset = .seconds(31)
        rig.respond(status: 200, body: Self.goodAnthropicBody)
        let result = await rig.provider.candidates(for: context(), textView: editor)
        XCTAssertEqual(rig.requestCount, 2)
        XCTAssertEqual(result.map(\.label), ["x"], "The next trigger after the window sends a request again")
    }

    @MainActor
    func testServerErrorsAndOverloadBackOffForThirtySeconds() async {
        for status in [500, 503, 529] {
            let rig = Rig()
            rig.respond(status: status)
            let editor = makeEditor()
            _ = await rig.provider.candidates(for: context(), textView: editor)
            _ = await rig.provider.candidates(for: context(), textView: editor)
            XCTAssertEqual(rig.requestCount, 1, "HTTP \(status) should back off")
        }
        AIStubURLProtocol.handler = nil
    }

    @MainActor
    func testAuthenticationFailureBacksOffForFiveMinutes() async {
        let rig = Rig()
        defer { AIStubURLProtocol.handler = nil }
        rig.respond(status: 401, body: #"{"error":{"message":"invalid x-api-key"}}"#)
        let editor = makeEditor()
        _ = await rig.provider.candidates(for: context(), textView: editor)
        rig.offset = .seconds(299)
        _ = await rig.provider.candidates(for: context(), textView: editor)
        XCTAssertEqual(rig.requestCount, 1)
        rig.offset = .seconds(301)
        _ = await rig.provider.candidates(for: context(), textView: editor)
        XCTAssertEqual(rig.requestCount, 2, "After five minutes the next trigger asks again")
    }

    @MainActor
    func testForbiddenBacksOffLikeUnauthorized() async {
        let rig = Rig(backend: .openAI)
        defer { AIStubURLProtocol.handler = nil }
        rig.respond(status: 403)
        let editor = makeEditor()
        _ = await rig.provider.candidates(for: context(), textView: editor)
        rig.offset = .seconds(120)
        _ = await rig.provider.candidates(for: context(), textView: editor)
        XCTAssertEqual(rig.requestCount, 1)
    }

    @MainActor
    func testAnUnreachableNetworkBacksOffForSixtySeconds() async {
        let rig = Rig()
        defer { AIStubURLProtocol.handler = nil }
        rig.fail(with: .notConnectedToInternet)
        let editor = makeEditor()
        _ = await rig.provider.candidates(for: context(), textView: editor)
        rig.offset = .seconds(59)
        _ = await rig.provider.candidates(for: context(), textView: editor)
        XCTAssertEqual(rig.requestCount, 1)
        rig.offset = .seconds(61)
        _ = await rig.provider.candidates(for: context(), textView: editor)
        XCTAssertEqual(rig.requestCount, 2)
    }

    @MainActor
    func testChangingTheKeyOrProviderEndsTheBackOff() async {
        let rig = Rig()
        defer { AIStubURLProtocol.handler = nil }
        rig.respond(status: 401)
        let editor = makeEditor()
        _ = await rig.provider.candidates(for: context(), textView: editor)
        XCTAssertEqual(rig.requestCount, 1)

        rig.keychain.set("a-new-key", forKey: AISettings.keychainKey(for: .anthropic))
        _ = await rig.provider.candidates(for: context(), textView: editor)
        XCTAssertEqual(rig.requestCount, 2, "A new key is worth trying at once")

        rig.settings.backend = .openAICompatible
        rig.settings.baseURL = "http://localhost:11434/v1"
        _ = await rig.provider.candidates(for: context(), textView: editor)
        XCTAssertEqual(rig.requestCount, 3, "Another provider has its own back-off")
    }

    @MainActor
    func testOtherClientErrorsAndBadBodiesDoNotBackOff() async {
        let rig = Rig()
        defer { AIStubURLProtocol.handler = nil }
        rig.respond(status: 400, body: #"{"error":{"message":"bad"}}"#)
        let editor = makeEditor()
        _ = await rig.provider.candidates(for: context(), textView: editor)
        _ = await rig.provider.candidates(for: context(), textView: editor)
        XCTAssertEqual(rig.requestCount, 2)

        rig.respond(status: 200, body: "<html>not json</html>")
        let result = await rig.provider.candidates(for: context(), textView: editor)
        XCTAssertTrue(result.isEmpty, "A response the backend cannot read never becomes candidates")
        _ = await rig.provider.candidates(for: context(), textView: editor)
        XCTAssertEqual(rig.requestCount, 4)
    }

    @MainActor
    func testBackendLatencyIsRecordedUnderTheBackendName() async {
        let rig = Rig()
        defer { AIStubURLProtocol.handler = nil }
        rig.respond(status: 200, body: Self.goodAnthropicBody)
        _ = await rig.provider.candidates(for: context(), textView: makeEditor())
        XCTAssertEqual(rig.metrics.backendLatencies, ["ai.anthropic"])

        rig.settings.backend = .openAICompatible
        rig.settings.baseURL = "http://localhost:11434/v1"
        _ = await rig.provider.candidates(for: context(), textView: makeEditor())
        XCTAssertEqual(rig.metrics.backendLatencies, ["ai.anthropic", "ai.openAICompatible"])
    }

    func testStatusClassification() {
        XCTAssertEqual(CloudAICompletionProvider.backoffDuration(forStatus: 429), .seconds(30))
        XCTAssertEqual(CloudAICompletionProvider.backoffDuration(forStatus: 529), .seconds(30))
        XCTAssertEqual(CloudAICompletionProvider.backoffDuration(forStatus: 502), .seconds(30))
        XCTAssertEqual(CloudAICompletionProvider.backoffDuration(forStatus: 401), .seconds(300))
        XCTAssertEqual(CloudAICompletionProvider.backoffDuration(forStatus: 403), .seconds(300))
        XCTAssertNil(CloudAICompletionProvider.backoffDuration(forStatus: 400))
        XCTAssertNil(CloudAICompletionProvider.backoffDuration(forStatus: 404))
        XCTAssertNil(CloudAICompletionProvider.backoffDuration(forStatus: 200))
    }
}
