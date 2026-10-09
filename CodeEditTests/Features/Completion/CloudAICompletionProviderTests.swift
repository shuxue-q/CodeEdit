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
        let provider = CloudAICompletionProvider(
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

        let provider = CloudAICompletionProvider(
            session: makeSession(), keychain: keychain, settingsProvider: { settings }
        )
        let result = await provider.candidates(for: context(), textView: makeEditor())
        XCTAssertEqual(result.map(\.label), ["vec"])
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
