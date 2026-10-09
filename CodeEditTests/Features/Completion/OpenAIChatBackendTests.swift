//
//  OpenAIChatBackendTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest

@testable import CodeEdit

final class OpenAIChatBackendTests: XCTestCase {
    private let backend = OpenAIChatBackend(kind: .openAI)
    private let compatible = OpenAIChatBackend(kind: .openAICompatible)

    private let request = AICompletionRequest(
        before: "int main() {\n    pri",
        after: "\n}\n",
        prefix: "pri",
        languageId: "c",
        intentDescription: "a statement"
    )

    private func response(status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/chat/completions")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private func body(content: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "choices": [["index": 0, "message": ["role": "assistant", "content": content], "finish_reason": "stop"]]
        ])
    }

    // MARK: - Request shape

    func testRequestTargetsChatCompletionsWithBearerAuthorization() throws {
        let urlRequest = try backend.makeRequest(
            request, configuration: AIBackendConfiguration(model: "gpt-5", apiKey: "sk-test")
        )
        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(urlRequest.httpMethod, "POST")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "content-type"), "application/json")
    }

    func testRequestBodyCarriesTheDocumentedParameters() throws {
        let urlRequest = try backend.makeRequest(
            request, configuration: AIBackendConfiguration(model: "gpt-5", apiKey: "k")
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(urlRequest.httpBody)) as? [String: Any]
        )
        XCTAssertEqual(json["model"] as? String, "gpt-5")
        XCTAssertEqual(json["max_completion_tokens"] as? Int, 256)
        XCTAssertNil(json["max_tokens"], "OpenAI's current models reject max_tokens")
        XCTAssertNil(json["temperature"], "Some of OpenAI's models reject any temperature but the default")
        XCTAssertEqual(json["n"] as? Int, 1)
        XCTAssertEqual((json["response_format"] as? [String: Any])?["type"] as? String, "json_object")

        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user"])
        let system = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(system.contains("JSON"), "JSON mode requires the word JSON in the messages")
        XCTAssertTrue(system.contains(AICompletionPrompt.systemPrompt))
        let user = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertTrue(user.contains("pri<cursor/>\n}"))
        XCTAssertTrue(user.contains("Language: c"))
    }

    func testCompatibleServersKeepMaxTokensAndTemperature() throws {
        let urlRequest = try compatible.makeRequest(
            request,
            configuration: AIBackendConfiguration(
                model: "qwen2.5-coder", baseURL: URL(string: "http://localhost:11434/v1"), apiKey: ""
            )
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(urlRequest.httpBody)) as? [String: Any]
        )
        XCTAssertEqual(json["max_tokens"] as? Int, 256)
        XCTAssertEqual(json["temperature"] as? Double, 0.2)
        XCTAssertNil(json["max_completion_tokens"])
        XCTAssertEqual(json["n"] as? Int, 1)
        XCTAssertEqual((json["response_format"] as? [String: Any])?["type"] as? String, "json_object")
    }

    func testTheParameterStyleFollowsTheKindUnlessGiven() {
        XCTAssertEqual(OpenAIChatBackend(kind: .openAI).parameterStyle, .current)
        XCTAssertEqual(OpenAIChatBackend(kind: .openAICompatible).parameterStyle, .legacy)
        XCTAssertEqual(OpenAIChatBackend(kind: .openAI, parameterStyle: .legacy).parameterStyle, .legacy)
    }

    // MARK: - Alternative wording after a refusal

    private func rejection(_ error: [String: Any], status: Int = 400) -> (Data, HTTPURLResponse) {
        // swiftlint:disable:next force_try
        (try! JSONSerialization.data(withJSONObject: ["error": error]), response(status: status))
    }

    func testAParameterRefusalOffersTheOtherWording() {
        let refusals: [[String: Any]] = [
            ["message": "Unsupported parameter: 'max_tokens' is not supported with this model."],
            ["message": "Unsupported value: 'temperature' does not support 0.2.", "code": "unsupported_value"],
            ["message": "Bad request", "code": "unsupported_value"],
            ["message": "Something is wrong", "param": "temperature"],
            ["message": "Unsupported parameter: 'max_completion_tokens'"]
        ]
        for error in refusals {
            let (data, response) = rejection(error)
            let alternative = backend.alternative(afterRejection: data, response: response) as? OpenAIChatBackend
            XCTAssertEqual(alternative?.parameterStyle, .legacy, "\(error)")
            XCTAssertEqual(alternative?.kind, .openAI)
        }
        let (data, response) = rejection(["message": "Unsupported parameter: 'max_tokens'"])
        let back = compatible.alternative(afterRejection: data, response: response) as? OpenAIChatBackend
        XCTAssertEqual(back?.parameterStyle, .current)
        XCTAssertEqual(back?.kind, .openAICompatible)
    }

    func testOtherRefusalsOfferNothing() {
        let (modelData, modelResponse) = rejection(["message": "No such model `nope`", "code": "model_not_found"])
        XCTAssertNil(backend.alternative(afterRejection: modelData, response: modelResponse))
        let (data, notBadRequest) = rejection(["message": "Unsupported parameter: 'temperature'"], status: 422)
        XCTAssertNil(backend.alternative(afterRejection: data, response: notBadRequest))
        XCTAssertNil(backend.alternative(afterRejection: Data("not json".utf8), response: response(status: 400)))
        XCTAssertNil(AnthropicMessagesBackend().alternative(afterRejection: data, response: response(status: 400)))
    }

    func testCustomBaseURLAndTrailingSlashAreHandled() throws {
        for base in ["http://localhost:11434/v1", "http://localhost:11434/v1/"] {
            let urlRequest = try compatible.makeRequest(
                request,
                configuration: AIBackendConfiguration(model: "qwen2.5-coder", baseURL: URL(string: base), apiKey: "")
            )
            XCTAssertEqual(urlRequest.url?.absoluteString, "http://localhost:11434/v1/chat/completions")
        }
    }

    func testExtraHeadersAreSent() throws {
        let urlRequest = try backend.makeRequest(
            request,
            configuration: AIBackendConfiguration(model: "m", apiKey: "k", extraHeaders: ["OpenAI-Organization": "org"])
        )
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "OpenAI-Organization"), "org")
    }

    // MARK: - API key rules

    func testLoopbackServerNeedsNoKeyAndSendsNoAuthorization() throws {
        for host in ["http://localhost:1234/v1", "http://127.0.0.1:11434/v1", "http://[::1]:8080/v1"] {
            let urlRequest = try compatible.makeRequest(
                request, configuration: AIBackendConfiguration(model: "m", baseURL: URL(string: host), apiKey: "")
            )
            XCTAssertNil(urlRequest.value(forHTTPHeaderField: "Authorization"), host)
        }
    }

    func testRemoteServerWithoutAKeyIsRejected() {
        let keyless = AIBackendConfiguration(model: "m", apiKey: "")
        XCTAssertThrowsError(try backend.makeRequest(request, configuration: keyless)) {
            guard case .invalidConfiguration = $0 as? AIBackendError else { return XCTFail("\($0)") }
        }
        let remote = AIBackendConfiguration(model: "m", baseURL: URL(string: "https://api.deepseek.com/v1"), apiKey: "")
        XCTAssertThrowsError(try compatible.makeRequest(request, configuration: remote))
    }

    func testCompatibleBackendRequiresABaseURL() {
        let configuration = AIBackendConfiguration(model: "m", apiKey: "k")
        XCTAssertThrowsError(try compatible.makeRequest(request, configuration: configuration))
    }

    // MARK: - Response shapes

    func testJSONObjectOfStringsDecodes() throws {
        let data = try body(content: #"{"completions": ["printf(\"%d\", x);", "puts(\"\");"]}"#)
        let result = try backend.suggestions(from: data, response: response())
        XCTAssertEqual(result.map(\.insertText), [#"printf("%d", x);"#, #"puts("");"#])
        XCTAssertEqual(result.first?.label, #"printf("%d", x);"#)
    }

    func testJSONObjectOfLabelledObjectsDecodes() throws {
        let data = try body(content: #"{"completions": [{"label": "printf", "insertText": "printf($0);"}]}"#)
        let result = try backend.suggestions(from: data, response: response())
        XCTAssertEqual(result, [AICompletionSuggestion(label: "printf", insertText: "printf($0);")])
    }

    func testFencedJSONArrayDecodes() throws {
        let data = try body(content: "```json\n[\"foo()\", \"bar()\"]\n```")
        XCTAssertEqual(try backend.suggestions(from: data, response: response()).map(\.insertText), ["foo()", "bar()"])
    }

    func testBareJSONArrayDecodes() throws {
        let data = try body(content: "[\"foo()\"]")
        XCTAssertEqual(try backend.suggestions(from: data, response: response()).map(\.insertText), ["foo()"])
    }

    func testPlainTextFallsBackToOneSuggestionPerLine() throws {
        let data = try body(content: "std::vector<int> v;\n\n  std::string s;\n")
        let result = try backend.suggestions(from: data, response: response())
        XCTAssertEqual(result.map(\.insertText), ["std::vector<int> v;", "std::string s;"])
    }

    func testEmptyCompletionsYieldNoSuggestions() throws {
        let data = try body(content: #"{"completions": []}"#)
        XCTAssertTrue(try backend.suggestions(from: data, response: response()).isEmpty)
    }

    func testContentGivenAsPartsDecodes() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": [["type": "text", "text": "{\"completions\": [\"x\"]}"]]]]]
        ])
        XCTAssertEqual(try backend.suggestions(from: data, response: response()).map(\.insertText), ["x"])
    }

    // MARK: - Errors

    func testErrorEnvelopeThrowsWithTheServerMessage() {
        let data = Data(#"{"error": {"message": "Incorrect API key provided", "type": "invalid_request_error"}}"#.utf8)
        XCTAssertThrowsError(try backend.suggestions(from: data, response: response(status: 401))) {
            XCTAssertEqual($0 as? AIBackendError, .server(status: 401, message: "Incorrect API key provided"))
        }
    }

    func testNon2xxWithoutEnvelopeThrowsAServerError() {
        XCTAssertThrowsError(try backend.suggestions(from: Data("<html>".utf8), response: response(status: 502))) {
            XCTAssertEqual($0 as? AIBackendError, .server(status: 502, message: nil))
        }
    }

    func testBodyWithoutChoicesIsMalformed() {
        XCTAssertThrowsError(try backend.suggestions(from: Data("{}".utf8), response: response())) {
            XCTAssertEqual($0 as? AIBackendError, .malformedResponse)
        }
    }

    func testBackendKindFactoryMapsEveryKind() {
        XCTAssertEqual(AIBackendKind.anthropic.backend.kind, .anthropic)
        XCTAssertEqual(AIBackendKind.openAI.backend.kind, .openAI)
        XCTAssertEqual(AIBackendKind.openAICompatible.backend.kind, .openAICompatible)
    }
}
