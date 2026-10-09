//
//  CloudAICompletionProviderWordingTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import CodeEditLanguages
@testable import CodeEditSourceEditor
import XCTest

@testable import CodeEdit

/// How the AI provider retries a request whose parameters the server refused, and what it remembers.
final class CloudAICompletionProviderWordingTests: XCTestCase {
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

    /// The request body as text. `URLSession` hands a protocol the body as a stream.
    private static func bodyText(of request: URLRequest) -> String {
        if let data = request.httpBody { return String(data: data, encoding: .utf8) ?? "" }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            guard bytesRead > 0 else { break }
            data.append(buffer, count: bytesRead)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// The request bodies the stub server received, safe to append to from the network thread.
    private final class BodyRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [String] = []

        var bodies: [String] { lock.withLock { all } }
        func record(_ body: String) { lock.withLock { all.append(body) } }
        func clear() { lock.withLock { all.removeAll() } }
    }

    /// A provider wired to the stub network.
    @MainActor
    private final class Rig {
        var settings = AISettings()
        let recorder = BodyRecorder()
        var bodies: [String] { recorder.bodies }
        let keychain = CodeEditKeychain(keyPrefix: "test.\(UUID().uuidString).")
        lazy var provider = CloudAICompletionProvider(
            session: AIStubURLProtocol.makeSession(),
            keychain: keychain,
            settingsProvider: { [unowned self] in settings }
        )

        init(backend: AIBackendKind) {
            settings.enabled = true
            settings.backend = backend
            if backend == .openAICompatible { settings.baseURL = "http://localhost:11434/v1" }
            keychain.set("key", forKey: AISettings.keychainKey(for: backend))
        }

        /// Refuses, with a 400 naming the parameter, every body that contains `"<name>"` for one of `refused`;
        /// answers the others with one suggestion, `x`.
        func serve(refusing refused: [String]) {
            let recorder = self.recorder
            AIStubURLProtocol.handler = { request in
                let body = CloudAICompletionProviderWordingTests.bodyText(of: request)
                recorder.record(body)
                let json: [String: Any]
                let status: Int
                if let name = refused.first(where: { body.contains("\"\($0)\"") }) {
                    status = 400
                    json = ["error": ["message": "Unsupported parameter: '\(name)' is not supported with this model."]]
                } else {
                    status = 200
                    json = ["choices": [["message": ["content": "[\"x\"]"]]]]
                }
                let data = try JSONSerialization.data(withJSONObject: json)
                let url = request.url!
                return (HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, data)
            }
        }
    }

    override func tearDown() {
        AIStubURLProtocol.handler = nil
        super.tearDown()
    }

    @MainActor
    func testAModelThatRefusesTheCurrentWordingIsRetriedOnceWithTheOldOne() async {
        let rig = Rig(backend: .openAI)
        rig.serve(refusing: ["max_completion_tokens"])
        let result = await rig.provider.candidates(for: context(), textView: makeEditor())
        XCTAssertEqual(result.map(\.label), ["x"])
        XCTAssertEqual(rig.bodies.count, 2, "One refusal, one retry")
        XCTAssertTrue(rig.bodies[0].contains("\"max_completion_tokens\""))
        XCTAssertFalse(rig.bodies[0].contains("\"temperature\""))
        XCTAssertTrue(rig.bodies[1].contains("\"max_tokens\""))
        XCTAssertTrue(rig.bodies[1].contains("\"temperature\""))
        XCTAssertFalse(rig.bodies[1].contains("\"max_completion_tokens\""))
    }

    @MainActor
    func testTheAcceptedWordingIsRememberedUntilTheConfigurationChanges() async {
        let rig = Rig(backend: .openAI)
        rig.serve(refusing: ["max_completion_tokens"])
        _ = await rig.provider.candidates(for: context(), textView: makeEditor())
        XCTAssertEqual(rig.bodies.count, 2)

        rig.recorder.clear()
        let again = await rig.provider.candidates(for: context(), textView: makeEditor())
        XCTAssertEqual(again.map(\.label), ["x"])
        XCTAssertEqual(rig.bodies.count, 1, "The working wording is sent straight away")
        XCTAssertTrue(rig.bodies[0].contains("\"max_tokens\""))

        rig.recorder.clear()
        rig.settings.model = "gpt-4o"
        _ = await rig.provider.candidates(for: context(), textView: makeEditor())
        XCTAssertEqual(rig.bodies.count, 2, "Another model is tried with the default wording again")
        XCTAssertTrue(rig.bodies[0].contains("\"max_completion_tokens\""))
    }

    @MainActor
    func testARefusalIsRetriedOnlyOnce() async {
        let rig = Rig(backend: .openAI)
        rig.serve(refusing: ["max_completion_tokens", "max_tokens"])
        let result = await rig.provider.candidates(for: context(), textView: makeEditor())
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(rig.bodies.count, 2, "The retry is not retried")
    }

    @MainActor
    func testACompatibleServerThatWantsTheNewWordingIsRetriedToo() async {
        let rig = Rig(backend: .openAICompatible)
        rig.serve(refusing: ["max_tokens"])
        let result = await rig.provider.candidates(for: context(), textView: makeEditor())
        XCTAssertEqual(result.map(\.label), ["x"])
        XCTAssertEqual(rig.bodies.count, 2)
        XCTAssertTrue(rig.bodies[1].contains("\"max_completion_tokens\""))
    }

    @MainActor
    func testARefusalThatNamesNoParameterIsNotRetried() async {
        let rig = Rig(backend: .openAI)
        let recorder = rig.recorder
        AIStubURLProtocol.handler = { request in
            recorder.record("")
            let error = ["error": ["message": "The model `nope` does not exist", "code": "model_not_found"]]
            let data = try JSONSerialization.data(withJSONObject: error)
            return (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!, data)
        }
        _ = await rig.provider.candidates(for: context(), textView: makeEditor())
        XCTAssertEqual(rig.bodies.count, 1)
    }
}
