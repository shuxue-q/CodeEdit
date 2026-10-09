//
//  CloudAICompletionProviderBackoffTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest

@testable import CodeEdit

/// How the AI provider backs off after failures, and the latency it reports.
final class CloudAICompletionProviderBackoffTests: XCTestCase {
    private typealias AISettings = AIProviderRig.AISettings

    @MainActor
    func testRateLimitBacksOffForThirtySecondsThenRetries() async {
        let rig = AIProviderRig()
        defer { AIStubURLProtocol.handler = nil }
        rig.respond(status: 429)
        let editor = makeAITestEditor()
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        XCTAssertEqual(rig.requestCount, 1)

        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        rig.offset = .seconds(29)
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        XCTAssertEqual(rig.requestCount, 1, "No request while backed off")

        rig.offset = .seconds(31)
        rig.respond(status: 200, body: AIProviderRig.goodAnthropicBody)
        let result = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        XCTAssertEqual(rig.requestCount, 2)
        XCTAssertEqual(result.map(\.label), ["x"], "The next trigger after the window sends a request again")
    }

    @MainActor
    func testServerErrorsAndOverloadBackOffForThirtySeconds() async {
        for status in [500, 503, 529] {
            let rig = AIProviderRig()
            rig.respond(status: status)
            let editor = makeAITestEditor()
            _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
            _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
            XCTAssertEqual(rig.requestCount, 1, "HTTP \(status) should back off")
        }
        AIStubURLProtocol.handler = nil
    }

    @MainActor
    func testAuthenticationFailureBacksOffForFiveMinutes() async {
        let rig = AIProviderRig()
        defer { AIStubURLProtocol.handler = nil }
        rig.respond(status: 401, body: #"{"error":{"message":"invalid x-api-key"}}"#)
        let editor = makeAITestEditor()
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        rig.offset = .seconds(299)
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        XCTAssertEqual(rig.requestCount, 1)
        rig.offset = .seconds(301)
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        XCTAssertEqual(rig.requestCount, 2, "After five minutes the next trigger asks again")
    }

    @MainActor
    func testForbiddenBacksOffLikeUnauthorized() async {
        let rig = AIProviderRig(backend: .openAI)
        defer { AIStubURLProtocol.handler = nil }
        rig.respond(status: 403)
        let editor = makeAITestEditor()
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        rig.offset = .seconds(120)
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        XCTAssertEqual(rig.requestCount, 1)
    }

    @MainActor
    func testAnUnreachableNetworkBacksOffForSixtySeconds() async {
        let rig = AIProviderRig()
        defer { AIStubURLProtocol.handler = nil }
        rig.fail(with: .notConnectedToInternet)
        let editor = makeAITestEditor()
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        rig.offset = .seconds(59)
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        XCTAssertEqual(rig.requestCount, 1)
        rig.offset = .seconds(61)
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        XCTAssertEqual(rig.requestCount, 2)
    }

    @MainActor
    func testChangingTheKeyOrProviderEndsTheBackOff() async {
        let rig = AIProviderRig()
        defer { AIStubURLProtocol.handler = nil }
        rig.respond(status: 401)
        let editor = makeAITestEditor()
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        XCTAssertEqual(rig.requestCount, 1)

        rig.keychain.set("a-new-key", forKey: AISettings.keychainKey(for: .anthropic))
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        XCTAssertEqual(rig.requestCount, 2, "A new key is worth trying at once")

        rig.settings.backend = .openAICompatible
        rig.settings.baseURL = "http://localhost:11434/v1"
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        XCTAssertEqual(rig.requestCount, 3, "Another provider has its own back-off")
    }

    @MainActor
    func testOtherClientErrorsAndBadBodiesDoNotBackOff() async {
        let rig = AIProviderRig()
        defer { AIStubURLProtocol.handler = nil }
        rig.respond(status: 409, body: #"{"error":{"message":"conflict"}}"#)
        let editor = makeAITestEditor()
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        XCTAssertEqual(rig.requestCount, 2)

        rig.respond(status: 200, body: "<html>not json</html>")
        let result = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        XCTAssertTrue(result.isEmpty, "A response the backend cannot read never becomes candidates")
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: editor)
        XCTAssertEqual(rig.requestCount, 4)
    }

    @MainActor
    func testBackendLatencyIsRecordedUnderTheBackendName() async {
        let rig = AIProviderRig()
        defer { AIStubURLProtocol.handler = nil }
        rig.respond(status: 200, body: AIProviderRig.goodAnthropicBody)
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: makeAITestEditor())
        XCTAssertEqual(rig.metrics.backendLatencies, ["ai.anthropic"])

        rig.settings.backend = .openAICompatible
        rig.settings.baseURL = "http://localhost:11434/v1"
        _ = await rig.provider.candidates(for: makeAITestContext(), textView: makeAITestEditor())
        XCTAssertEqual(rig.metrics.backendLatencies, ["ai.anthropic", "ai.openAICompatible"])
    }

    func testStatusClassification() {
        XCTAssertEqual(CloudAICompletionProvider.backoffDuration(forStatus: 429), .seconds(30))
        XCTAssertEqual(CloudAICompletionProvider.backoffDuration(forStatus: 529), .seconds(30))
        XCTAssertEqual(CloudAICompletionProvider.backoffDuration(forStatus: 502), .seconds(30))
        XCTAssertEqual(CloudAICompletionProvider.backoffDuration(forStatus: 401), .seconds(300))
        XCTAssertEqual(CloudAICompletionProvider.backoffDuration(forStatus: 403), .seconds(300))
        XCTAssertEqual(CloudAICompletionProvider.backoffDuration(forStatus: 400), .seconds(120))
        XCTAssertEqual(CloudAICompletionProvider.backoffDuration(forStatus: 404), .seconds(120))
        XCTAssertEqual(CloudAICompletionProvider.backoffDuration(forStatus: 422), .seconds(120))
        XCTAssertNil(CloudAICompletionProvider.backoffDuration(forStatus: 409))
        XCTAssertNil(CloudAICompletionProvider.backoffDuration(forStatus: 200))
    }
}
