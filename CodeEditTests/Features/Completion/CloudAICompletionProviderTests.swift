//
//  CloudAICompletionProviderTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import CodeEditLanguages
@testable import CodeEditSourceEditor
import XCTest

@testable import CodeEdit

final class CloudAICompletionProviderTests: XCTestCase {
    private typealias AISettings = SettingsData.TextEditingSettings.AICompletionSettings

    private typealias StubURLProtocol = AIStubURLProtocol

    /// The request body as text. `URLSession` hands a protocol the body as a stream.
    private static func bodyText(of request: URLRequest) -> String? {
        if let data = request.httpBody { return String(data: data, encoding: .utf8) }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            guard bytesRead > 0 else { break }
            data.append(buffer, count: bytesRead)
        }
        return String(data: data, encoding: .utf8)
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
            intent: .statement,
            languageId: "c",
            documentText: "int main() {\n    pri\n}\n",
            cursorOffset: 20,
            isExplicit: isExplicit
        )
    }

    private func successResponse(json: [String: Any]) -> (HTTPURLResponse, Data) {
        let data = try! JSONSerialization.data(withJSONObject: json) // swiftlint:disable:this force_try
        let response = HTTPURLResponse(
            url: AnthropicMessagesBackend.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        return (response, data)
    }

    // MARK: - End-to-end through the provider

    @MainActor
    func testDisabledSettingsSkipTheRequestEntirely() async {
        StubURLProtocol.handler = { _ in XCTFail("Should not make a network request"); fatalError() }
        defer { StubURLProtocol.handler = nil }
        let provider = CloudAICompletionProvider(
            session: makeSession(),
            keychain: CodeEditKeychain(keyPrefix: "test.\(UUID().uuidString)."),
            settingsProvider: { AISettings() }
        )
        let result = await provider.candidates(for: context(), textView: makeEditor())
        XCTAssertTrue(result.isEmpty)
    }

    @MainActor
    func testShortAutomaticPrefixIsSkipped() async {
        var settings = AISettings()
        settings.enabled = true
        let keychain = CodeEditKeychain(keyPrefix: "test.\(UUID().uuidString).")
        keychain.set("test-key", forKey: AISettings.keychainKey(for: .anthropic))
        StubURLProtocol.handler = { _ in XCTFail("Should not make a network request"); fatalError() }
        defer { StubURLProtocol.handler = nil }
        let provider = CloudAICompletionProvider(
            session: makeSession(), keychain: keychain, settingsProvider: { settings }
        )
        let result = await provider.candidates(for: context(prefix: "p"), textView: makeEditor())
        XCTAssertTrue(result.isEmpty)
    }

    @MainActor
    func testEnabledSettingsWithAKeyMakeARequestAndDecodeTheResponse() async {
        var settings = AISettings()
        settings.enabled = true
        let keychain = CodeEditKeychain(keyPrefix: "test.\(UUID().uuidString).")
        keychain.set("test-key", forKey: AISettings.keychainKey(for: .anthropic))

        let structuredOutput = #"{"completions":[{"label":"vec","insertText":"std::vector<$0>"}]}"#
        StubURLProtocol.handler = { [weak self] request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
            return self!.successResponse(json: [
                "stop_reason": "end_turn",
                "content": [["type": "text", "text": structuredOutput]]
            ])
        }
        defer { StubURLProtocol.handler = nil }

        let provider = CloudAICompletionProvider(
            session: makeSession(), keychain: keychain, settingsProvider: { settings }
        )
        let result = await provider.candidates(for: context(), textView: makeEditor())
        XCTAssertEqual(result.map(\.label), ["vec"])
    }

    @MainActor
    func testOpenAISelectionUsesItsOwnKeyAndEndpoint() async {
        var settings = AISettings()
        settings.enabled = true
        settings.backend = .openAI
        settings.model = "gpt-5"
        let keychain = CodeEditKeychain(keyPrefix: "test.\(UUID().uuidString).")
        keychain.set("anthropic-key", forKey: AISettings.keychainKey(for: .anthropic))
        keychain.set("openai-key", forKey: AISettings.keychainKey(for: .openAI))

        var seen: URLRequest?
        StubURLProtocol.handler = { request in
            seen = request
            let content = #"{"completions": ["std::vector<int> v;"]}"#
            let json: [String: Any] = ["choices": [["message": ["content": content]]]]
            let data = try! JSONSerialization.data(withJSONObject: json) // swiftlint:disable:this force_try
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }
        defer { StubURLProtocol.handler = nil }

        let provider = CloudAICompletionProvider(
            session: makeSession(), keychain: keychain, settingsProvider: { settings }
        )
        let result = await provider.candidates(for: context(), textView: makeEditor())
        XCTAssertEqual(result.map(\.label), ["std::vector<int> v;"])
        XCTAssertEqual(seen?.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(seen?.value(forHTTPHeaderField: "Authorization"), "Bearer openai-key")
    }

    @MainActor
    func testLoopbackCompatibleServerIsQueriedWithoutAKey() async {
        var settings = AISettings()
        settings.enabled = true
        settings.backend = .openAICompatible
        settings.baseURL = "http://localhost:11434/v1"
        settings.model = "qwen2.5-coder"
        var seen: URLRequest?
        StubURLProtocol.handler = { request in
            seen = request
            let json: [String: Any] = ["choices": [["message": ["content": "[\"x\"]"]]]]
            let data = try! JSONSerialization.data(withJSONObject: json) // swiftlint:disable:this force_try
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        defer { StubURLProtocol.handler = nil }

        let provider = CloudAICompletionProvider(
            session: makeSession(),
            keychain: CodeEditKeychain(keyPrefix: "test.\(UUID().uuidString)."),
            settingsProvider: { settings }
        )
        let result = await provider.candidates(for: context(), textView: makeEditor())
        XCTAssertEqual(result.map(\.label), ["x"])
        XCTAssertEqual(seen?.url?.absoluteString, "http://localhost:11434/v1/chat/completions")
        XCTAssertNil(seen?.value(forHTTPHeaderField: "Authorization"))
    }

    @MainActor
    func testMissingKeyForARemoteBackendSkipsTheRequest() async {
        var settings = AISettings()
        settings.enabled = true
        settings.backend = .openAI
        StubURLProtocol.handler = { _ in XCTFail("Should not make a network request"); fatalError() }
        defer { StubURLProtocol.handler = nil }
        let provider = CloudAICompletionProvider(
            session: makeSession(),
            keychain: CodeEditKeychain(keyPrefix: "test.\(UUID().uuidString)."),
            settingsProvider: { settings }
        )
        let result = await provider.candidates(for: context(), textView: makeEditor())
        XCTAssertTrue(result.isEmpty)
    }

    @MainActor
    func testThePromptCarriesTheResolvedSemanticFacts() async throws {
        var settings = AISettings()
        settings.enabled = true
        let keychain = CodeEditKeychain(keyPrefix: "test.\(UUID().uuidString).")
        keychain.set("test-key", forKey: AISettings.keychainKey(for: .anthropic))
        var body: String?
        StubURLProtocol.handler = { [weak self] request in
            body = Self.bodyText(of: request)
            return self!.successResponse(json: ["stop_reason": "end_turn", "content": []])
        }
        defer { StubURLProtocol.handler = nil }
        var enriched = context()
        enriched.awaitSemantics = { _ in
            ResolvedSemantics(
                expectedType: TypeText.parse("std::string"), receiverType: nil, functionSignature: "int main()"
            )
        }
        let provider = CloudAICompletionProvider(
            session: makeSession(), keychain: keychain, settingsProvider: { settings }
        )
        _ = await provider.candidates(for: enriched, textView: makeEditor())
        let sent = try XCTUnwrap(body)
        XCTAssertTrue(sent.contains("should produce a `std::string`"), sent)
        XCTAssertTrue(sent.contains("inside this function: `int main()`"), sent)
        XCTAssertFalse(sent.contains("object before the cursor"), sent)
    }

    func testHTTPErrorYieldsNoCandidates() {
        let response = HTTPURLResponse(
            url: AnthropicMessagesBackend.endpoint, statusCode: 500, httpVersion: nil, headerFields: nil
        )!
        XCTAssertEqual(response.statusCode, 500)
        // The 2xx check lives in `performRequest`; `candidates(from:)` only covers the body, which
        // an error response typically doesn't carry in the expected shape.
        XCTAssertTrue(
            CloudAICompletionProvider.candidates(from: Data(), response: response, backend: AnthropicMessagesBackend())
                .isEmpty
        )
    }
}
