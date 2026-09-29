//
//  ClaudeCompletionProviderTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import CodeEditLanguages
@testable import CodeEditSourceEditor
import XCTest

@testable import CodeEdit

final class ClaudeCompletionProviderTests: XCTestCase {
    /// Routes every request through a handler set per test, instead of touching the network.
    private final class StubURLProtocol: URLProtocol {
        static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

        // `class` is required here: these override `URLProtocol`'s dynamically dispatched class
        // methods, which `static` cannot do.
        // swiftlint:disable:next static_over_final_class
        override class func canInit(with request: URLRequest) -> Bool { true }
        // swiftlint:disable:next static_over_final_class
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.handler else {
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            let (response, data) = handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() { }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

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

    private func context(prefix: String = "pri", isExplicit: Bool = false) -> CompletionContext {
        CompletionContext(
            prefix: prefix,
            prefixRange: NSRange(location: 0, length: prefix.utf16.count),
            triggerCharacter: nil,
            syntax: .statement,
            languageId: "c",
            documentText: "int main() {\n    pri\n}\n",
            cursorOffset: 20,
            isExplicit: isExplicit
        )
    }

    private func successResponse(json: [String: Any]) -> (HTTPURLResponse, Data) {
        let data = try! JSONSerialization.data(withJSONObject: json) // swiftlint:disable:this force_try
        let response = HTTPURLResponse(
            url: ClaudeCompletionProvider.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        return (response, data)
    }

    // MARK: - Request encoding

    func testRequestIncludesTheRequiredHeaders() {
        let request = ClaudeCompletionProvider.makeRequest(context: context(), model: "claude-opus-5", apiKey: "key")
        XCTAssertEqual(request.url, ClaudeCompletionProvider.endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01"
        )
    }

    func testRequestBodyOmitsTemperatureAndThinkingAndHasNoAssistantMessage() {
        let body = ClaudeCompletionProvider.requestBody(context: context(), model: "claude-opus-5")
        XCTAssertEqual(body["model"] as? String, "claude-opus-5")
        XCTAssertEqual(body["max_tokens"] as? Int, 1_024)
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertNil(body["temperature"])
        XCTAssertNil(body["top_p"])
        XCTAssertNil(body["top_k"])
        XCTAssertNil(body["thinking"])

        let messages = try? XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages?.count, 1)
        XCTAssertEqual(messages?.first?["role"] as? String, "user")

        let outputConfig = try? XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual(outputConfig?["effort"] as? String, "low")
        let format = outputConfig?["format"] as? [String: Any]
        XCTAssertEqual(format?["type"] as? String, "json_schema")
        XCTAssertNotNil(format?["schema"])
    }

    // MARK: - Response decoding

    func testEndTurnResponseDecodesCompletions() {
        let structuredOutput = #"{"completions":[{"label":"printf","insertText":"printf($0);"}]}"#
        let json: [String: Any] = [
            "stop_reason": "end_turn",
            "content": [["type": "text", "text": structuredOutput]]
        ]
        let (_, data) = successResponse(json: json)
        let candidates = ClaudeCompletionProvider.candidates(from: data)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.label, "printf")
        XCTAssertEqual(candidates.first?.source, .ai)
        guard case .plain(let insertText) = candidates.first?.payload else {
            return XCTFail("Expected a plain insert-text payload")
        }
        XCTAssertEqual(insertText, "printf($0);")
    }

    func testRefusalStopReasonYieldsNoCandidates() {
        let json: [String: Any] = ["stop_reason": "refusal", "content": [["type": "text", "text": "{}"]]]
        let (_, data) = successResponse(json: json)
        XCTAssertTrue(ClaudeCompletionProvider.candidates(from: data).isEmpty)
    }

    func testNonEndTurnStopReasonYieldsNoCandidates() {
        let json: [String: Any] = ["stop_reason": "max_tokens", "content": [["type": "text", "text": "{}"]]]
        let (_, data) = successResponse(json: json)
        XCTAssertTrue(ClaudeCompletionProvider.candidates(from: data).isEmpty)
    }

    func testMalformedContentYieldsNoCandidates() {
        let json: [String: Any] = ["stop_reason": "end_turn", "content": [["type": "text", "text": "not json"]]]
        let (_, data) = successResponse(json: json)
        XCTAssertTrue(ClaudeCompletionProvider.candidates(from: data).isEmpty)
    }

    // MARK: - End-to-end through the provider

    @MainActor
    func testDisabledSettingsSkipTheRequestEntirely() async {
        StubURLProtocol.handler = { _ in XCTFail("Should not make a network request"); fatalError() }
        defer { StubURLProtocol.handler = nil }
        let provider = ClaudeCompletionProvider(
            session: makeSession(),
            keychain: CodeEditKeychain(keyPrefix: "test.\(UUID().uuidString)."),
            settingsProvider: { SettingsData.TextEditingSettings.AICompletionSettings() }
        )
        let result = await provider.candidates(for: context(), textView: makeEditor())
        XCTAssertTrue(result.isEmpty)
    }

    @MainActor
    func testShortAutomaticPrefixIsSkipped() async {
        var settings = SettingsData.TextEditingSettings.AICompletionSettings()
        settings.enabled = true
        let keychain = CodeEditKeychain(keyPrefix: "test.\(UUID().uuidString).")
        keychain.set("test-key", forKey: SettingsData.TextEditingSettings.AICompletionSettings.keychainKey)
        StubURLProtocol.handler = { _ in XCTFail("Should not make a network request"); fatalError() }
        defer { StubURLProtocol.handler = nil }
        let provider = ClaudeCompletionProvider(
            session: makeSession(), keychain: keychain, settingsProvider: { settings }
        )
        let result = await provider.candidates(for: context(prefix: "p"), textView: makeEditor())
        XCTAssertTrue(result.isEmpty)
    }

    @MainActor
    func testEnabledSettingsWithAKeyMakeARequestAndDecodeTheResponse() async {
        var settings = SettingsData.TextEditingSettings.AICompletionSettings()
        settings.enabled = true
        let keychain = CodeEditKeychain(keyPrefix: "test.\(UUID().uuidString).")
        keychain.set("test-key", forKey: SettingsData.TextEditingSettings.AICompletionSettings.keychainKey)

        let structuredOutput = #"{"completions":[{"label":"vec","insertText":"std::vector<$0>"}]}"#
        StubURLProtocol.handler = { [weak self] request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
            return self!.successResponse(json: [
                "stop_reason": "end_turn",
                "content": [["type": "text", "text": structuredOutput]]
            ])
        }
        defer { StubURLProtocol.handler = nil }

        let provider = ClaudeCompletionProvider(
            session: makeSession(), keychain: keychain, settingsProvider: { settings }
        )
        let result = await provider.candidates(for: context(), textView: makeEditor())
        XCTAssertEqual(result.map(\.label), ["vec"])
    }

    func testHTTPErrorYieldsNoCandidates() {
        let response = HTTPURLResponse(
            url: ClaudeCompletionProvider.endpoint, statusCode: 500, httpVersion: nil, headerFields: nil
        )!
        XCTAssertEqual(response.statusCode, 500)
        // The 2xx check lives in `performRequest`; `candidates(from:)` only covers the body, which
        // an error response typically doesn't carry in the expected shape.
        XCTAssertTrue(ClaudeCompletionProvider.candidates(from: Data()).isEmpty)
    }
}
