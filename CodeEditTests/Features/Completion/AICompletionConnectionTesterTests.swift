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

    func testStatusDescriptionWithoutAMessage() {
        XCTAssertEqual(AICompletionConnectionTester.describe(status: 503, message: nil), "503 Service Unavailable")
    }
}
