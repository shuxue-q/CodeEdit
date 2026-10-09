//
//  AnthropicMessagesBackendTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest

@testable import CodeEdit

final class AnthropicMessagesBackendTests: XCTestCase {
    private let backend = AnthropicMessagesBackend()

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

    /// The candidates the provider would surface for a 200 response with `data`.
    private func candidates(from data: Data) -> [CompletionCandidate] {
        let response = HTTPURLResponse(
            url: AnthropicMessagesBackend.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        return CloudAICompletionProvider.candidates(from: data, response: response, backend: backend)
    }

    // MARK: - Request encoding

    func testRequestIncludesTheRequiredHeaders() throws {
        let request = try backend.makeRequest(
            AICompletionPrompt.request(for: context()),
            configuration: AIBackendConfiguration(model: "claude-opus-5", apiKey: "key")
        )
        XCTAssertEqual(request.url, AnthropicMessagesBackend.endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01"
        )
    }

    func testRequestBodyOmitsTemperatureAndThinkingAndHasNoAssistantMessage() {
        let body = AnthropicMessagesBackend.requestBody(
            request: AICompletionPrompt.request(for: context()), model: "claude-opus-5"
        )
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
        let candidates = candidates(from: data)
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
        XCTAssertTrue(candidates(from: data).isEmpty)
    }

    func testNonEndTurnStopReasonYieldsNoCandidates() {
        let json: [String: Any] = ["stop_reason": "max_tokens", "content": [["type": "text", "text": "{}"]]]
        let (_, data) = successResponse(json: json)
        XCTAssertTrue(candidates(from: data).isEmpty)
    }

    func testMalformedContentYieldsNoCandidates() {
        let json: [String: Any] = ["stop_reason": "end_turn", "content": [["type": "text", "text": "not json"]]]
        let (_, data) = successResponse(json: json)
        XCTAssertTrue(candidates(from: data).isEmpty)
    }

    func testErrorStatusThrowsAServerErrorWithTheEnvelopeMessage() {
        let response = HTTPURLResponse(
            url: AnthropicMessagesBackend.endpoint, statusCode: 401, httpVersion: nil, headerFields: nil
        )!
        let body = Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)
        XCTAssertThrowsError(try backend.suggestions(from: body, response: response)) { error in
            XCTAssertEqual(error as? AIBackendError, .server(status: 401, message: "invalid x-api-key"))
        }
    }

    func testBaseURLOverridesTheDefaultEndpoint() throws {
        let custom = URL(string: "https://proxy.example.com/v1/messages")!
        let request = try backend.makeRequest(
            AICompletionPrompt.request(for: context()),
            configuration: AIBackendConfiguration(model: "m", baseURL: custom, apiKey: "k")
        )
        XCTAssertEqual(request.url, custom)
    }
}
