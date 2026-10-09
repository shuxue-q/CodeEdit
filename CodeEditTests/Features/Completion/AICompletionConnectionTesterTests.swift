//
//  AICompletionConnectionTesterTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest

@testable import CodeEdit

final class AICompletionConnectionTesterTests: XCTestCase {
    private let tester = AICompletionConnectionTester(session: AIStubURLProtocol.makeSession())

    override func tearDown() {
        AIStubURLProtocol.handler = nil
        super.tearDown()
    }

    private func respond(status: Int, json: [String: Any]) {
        AIStubURLProtocol.handler = { request in
            let data = try JSONSerialization.data(withJSONObject: json)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, data)
        }
    }

    func testSuccessReportsTheModelAndAnElapsedTime() async {
        respond(status: 200, json: ["choices": [["message": ["content": "{\"completions\": []}"]]]])
        let result = await tester.test(
            backend: OpenAIChatBackend(kind: .openAI),
            configuration: AIBackendConfiguration(model: "gpt-5", apiKey: "k")
        )
        guard case let .success(model, milliseconds) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(model, "gpt-5")
        XCTAssertGreaterThanOrEqual(milliseconds, 0)
    }

    func testTheTestRequestIsBoundedToFiveSecondsAndAsksForOneSuggestion() async {
        var seen: URLRequest?
        AIStubURLProtocol.handler = { request in
            seen = request
            let data = Data(#"{"choices": [{"message": {"content": "[]"}}]}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        _ = await tester.test(
            backend: OpenAIChatBackend(kind: .openAI),
            configuration: AIBackendConfiguration(model: "gpt-5", apiKey: "k")
        )
        XCTAssertEqual(seen?.timeoutInterval, 5)
    }

    func testUnauthorizedIsReportedWithTheStatusAndTheServersMessage() async {
        respond(status: 401, json: ["error": ["message": "Incorrect API key provided"]])
        let result = await tester.test(
            backend: OpenAIChatBackend(kind: .openAI),
            configuration: AIBackendConfiguration(model: "gpt-5", apiKey: "bad")
        )
        XCTAssertEqual(result, .failure(message: "401 Unauthorized: Incorrect API key provided"))
    }

    func testAnthropicErrorEnvelopeIsReported() async {
        respond(status: 404, json: ["type": "error", "error": ["message": "model: nope"]])
        let result = await tester.test(
            backend: AnthropicMessagesBackend(),
            configuration: AIBackendConfiguration(model: "nope", apiKey: "k")
        )
        XCTAssertEqual(result, .failure(message: "404 Not Found: model: nope"))
    }

    func testMissingKeyFailsWithoutAnyRequest() async {
        AIStubURLProtocol.handler = { _ in XCTFail("Should not make a network request"); throw URLError(.badURL) }
        let result = await tester.test(
            backend: AnthropicMessagesBackend(),
            configuration: AIBackendConfiguration(model: "m", apiKey: "")
        )
        XCTAssertEqual(result, .failure(message: "An API key is required."))
    }

    func testTimeoutIsReported() async {
        AIStubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        let result = await tester.test(
            backend: OpenAIChatBackend(kind: .openAI),
            configuration: AIBackendConfiguration(model: "m", apiKey: "k")
        )
        XCTAssertEqual(result, .failure(message: "No answer within 5 seconds"))
    }

    func testAnUnexpectedBodyIsReportedAsMalformed() async {
        respond(status: 200, json: ["unexpected": true])
        let result = await tester.test(
            backend: OpenAIChatBackend(kind: .openAI),
            configuration: AIBackendConfiguration(model: "m", apiKey: "k")
        )
        XCTAssertEqual(result, .failure(message: "The server answered, but not in the expected format"))
    }

    // MARK: - Back-off

    private let configuration = AIBackendConfiguration(model: "gpt-5", apiKey: "k")

    /// A tester with its own back-off store, and the stub server's request counter.
    private struct StoreRig {
        let tester: AICompletionConnectionTester
        let store: AICompletionBackoffStore
        let counter: AIRequestCounter

        var requests: Int { counter.value }
    }

    private func testerWithStore(statusOfAnswer status: Int, json: [String: Any]) -> StoreRig {
        let counter = AIRequestCounter()
        AIStubURLProtocol.handler = { request in
            counter.increment()
            let data = try JSONSerialization.data(withJSONObject: json)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, data)
        }
        let store = AICompletionBackoffStore()
        return StoreRig(
            tester: AICompletionConnectionTester(session: AIStubURLProtocol.makeSession(), backoffStore: store),
            store: store,
            counter: counter
        )
    }

    func testASuccessfulTestIgnoresAndClearsTheBackOff() async {
        let rig = testerWithStore(
            statusOfAnswer: 200, json: ["choices": [["message": ["content": "{\"completions\": []}"]]]]
        )
        let farFuture = ContinuousClock.now.advanced(by: .seconds(3_600))
        rig.store.start(until: farFuture, kind: .openAI, configuration: configuration)
        XCTAssertTrue(rig.store.isBackedOff(kind: .openAI, configuration: configuration, now: .now))

        let result = await rig.tester.test(backend: OpenAIChatBackend(kind: .openAI), configuration: configuration)
        guard case .success = result else { return XCTFail("\(result)") }
        XCTAssertEqual(rig.requests, 1, "The test sends its request although the providers are backed off")
        XCTAssertFalse(
            rig.store.isBackedOff(kind: .openAI, configuration: configuration, now: .now),
            "A working connection ends the back-off"
        )
    }

    func testAFailedTestIgnoresTheBackOffButKeepsIt() async {
        let rig = testerWithStore(statusOfAnswer: 404, json: ["error": ["message": "model: nope"]])
        let farFuture = ContinuousClock.now.advanced(by: .seconds(3_600))
        rig.store.start(until: farFuture, kind: .openAI, configuration: configuration)

        let result = await rig.tester.test(backend: OpenAIChatBackend(kind: .openAI), configuration: configuration)
        XCTAssertEqual(result, .failure(message: "404 Not Found: model: nope"))
        XCTAssertEqual(rig.requests, 1)
        XCTAssertTrue(rig.store.isBackedOff(kind: .openAI, configuration: configuration, now: .now))
    }

    func testASuccessfulTestLeavesTheBackOffOfAnotherConfiguration() async {
        let rig = testerWithStore(
            statusOfAnswer: 200, json: ["choices": [["message": ["content": "[]"]]]]
        )
        let other = AIBackendConfiguration(model: "gpt-4o", apiKey: "k")
        let farFuture = ContinuousClock.now.advanced(by: .seconds(3_600))
        rig.store.start(until: farFuture, kind: .openAI, configuration: other)

        _ = await rig.tester.test(backend: OpenAIChatBackend(kind: .openAI), configuration: configuration)
        XCTAssertTrue(rig.store.isBackedOff(kind: .openAI, configuration: other, now: .now))
    }

    func testTheTestRetriesOnceWithTheOtherParameterWording() async {
        let counter = AIRequestCounter()
        AIStubURLProtocol.handler = { request in
            counter.increment()
            let refused = counter.value == 1
            let json: [String: Any] = refused
                ? ["error": ["message": "Unsupported parameter: 'max_completion_tokens'"]]
                : ["choices": [["message": ["content": "[]"]]]]
            let data = try JSONSerialization.data(withJSONObject: json)
            let status = refused ? 400 : 200
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, data)
        }
        let result = await tester.test(backend: OpenAIChatBackend(kind: .openAI), configuration: configuration)
        guard case .success = result else { return XCTFail("\(result)") }
        XCTAssertEqual(counter.value, 2)
    }

    func testStatusDescriptionWithoutAMessage() {
        XCTAssertEqual(AICompletionConnectionTester.describe(status: 503, message: nil), "503 Service Unavailable")
    }
}
