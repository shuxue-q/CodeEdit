//
//  CloudAICompletionProviderRefusalTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest

@testable import CodeEdit

/// How the AI provider backs off when the server refuses the request itself (HTTP 400, 404, 422), which a
/// wrong model name or base URL does on every request.
final class CloudAICompletionProviderRefusalTests: XCTestCase {
    override func tearDown() {
        AIStubURLProtocol.handler = nil
        super.tearDown()
    }

    @MainActor
    func testARefusedRequestBacksOffForTwoMinutes() async {
        defer { AIStubURLProtocol.handler = nil }
        for status in [400, 404, 422] {
            let rig = AIProviderRig()
            rig.respond(status: status, body: #"{"error":{"message":"model: nope"}}"#)
            let editor = makeAITestEditor()
            _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
            XCTAssertEqual(rig.requestCount, 1)
            _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
            rig.offset = .seconds(119)
            _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
            XCTAssertEqual(rig.requestCount, 1, "HTTP \(status) pauses requests, not one per keystroke")

            rig.offset = .seconds(121)
            rig.respond(status: 200, body: AIProviderRig.goodAnthropicBody)
            let result = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
            XCTAssertEqual(rig.requestCount, 2)
            XCTAssertEqual(result.map(\.label), ["x"], "After two minutes the next trigger asks again (HTTP \(status))")
        }
    }

    @MainActor
    func testARefusedRequestPausesEveryProviderThatSharesTheStore() async {
        let rig = AIProviderRig()
        defer { AIStubURLProtocol.handler = nil }
        rig.respond(status: 404, body: #"{"error":{"message":"model: nope"}}"#)
        let editor = makeAITestEditor()
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        let other = rig.makeProvider()
        _ = await other.candidates(for: makeAITestContext(), textView: editor)
        XCTAssertEqual(rig.requestCount, 1, "A second document does not repeat the failing request")
    }

    @MainActor
    func testChangingTheModelOrBaseURLEndsTheRefusalBackOff() async {
        let rig = AIProviderRig(backend: .openAICompatible)
        defer { AIStubURLProtocol.handler = nil }
        rig.settings.baseURL = "http://localhost:11434/v1"
        rig.settings.model = "typo"
        rig.respond(status: 404, body: #"{"error":{"message":"model 'typo' not found"}}"#)
        let editor = makeAITestEditor()
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        XCTAssertEqual(rig.requestCount, 1)

        rig.settings.model = "qwen2.5-coder"
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        XCTAssertEqual(rig.requestCount, 2, "A corrected model name is tried at once")

        rig.settings.baseURL = "http://localhost:1234/v1"
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        XCTAssertEqual(rig.requestCount, 3, "A corrected base URL is tried at once")
    }

    @MainActor
    func testARefusalOfBothParameterWordingsBacksOffAfterTheRetry() async {
        let rig = AIProviderRig(backend: .openAI)
        defer { AIStubURLProtocol.handler = nil }
        rig.respond(status: 400, body: #"{"error":{"message":"Unsupported parameter: 'temperature'"}}"#)
        let editor = makeAITestEditor()
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        XCTAssertEqual(rig.requestCount, 2, "The wording is retried once, then the refusal stands")
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        XCTAssertEqual(rig.requestCount, 2)
    }
}
