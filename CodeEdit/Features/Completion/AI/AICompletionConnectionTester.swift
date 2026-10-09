//
//  AICompletionConnectionTester.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// What a connection test found.
enum AICompletionConnectionResult: Equatable, Sendable {
    /// The server answered a completion request; `milliseconds` is how long it took.
    case success(model: String, milliseconds: Int)
    /// The test failed; `message` is ready to show to the user.
    case failure(message: String)
}

/// Sends one minimal request through a backend, to check the provider, key, base URL and model from the
/// settings page. It never touches an editor, and it is bounded by ``timeout``.
struct AICompletionConnectionTester {
    /// How long a test may take before it is reported as a failure.
    static let timeout: TimeInterval = 5

    /// The session the request goes through. Injectable so tests can stub the network.
    var session: URLSession = .shared

    /// Tests `backend` with `configuration`.
    func test(
        backend: any AICompletionBackend,
        configuration: AIBackendConfiguration
    ) async -> AICompletionConnectionResult {
        let request = AICompletionRequest(
            before: "int main() {\n    ret",
            after: "\n}\n",
            prefix: "ret",
            languageId: "c",
            intentDescription: "a statement",
            maxSuggestions: 1
        )
        var urlRequest: URLRequest
        do {
            urlRequest = try backend.makeRequest(request, configuration: configuration)
        } catch let AIBackendError.invalidConfiguration(reason) {
            return .failure(message: reason)
        } catch {
            return .failure(message: error.localizedDescription)
        }
        urlRequest.timeoutInterval = Self.timeout

        let start = Date()
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { return .failure(message: "No HTTP response") }
            _ = try backend.suggestions(from: data, response: http)
            let milliseconds = Int(Date().timeIntervalSince(start) * 1_000)
            return .success(model: configuration.model, milliseconds: milliseconds)
        } catch let AIBackendError.server(status, message) {
            return .failure(message: Self.describe(status: status, message: message))
        } catch AIBackendError.malformedResponse {
            return .failure(message: "The server answered, but not in the expected format")
        } catch let error as URLError where error.code == .timedOut {
            return .failure(message: "No answer within \(Int(Self.timeout)) seconds")
        } catch {
            return .failure(message: error.localizedDescription)
        }
    }

    /// "401 Unauthorized", with the server's own explanation appended when it gave one.
    static func describe(status: Int, message: String?) -> String {
        let reason = HTTPURLResponse.localizedString(forStatusCode: status).capitalized
        guard let message, !message.isEmpty else { return "\(status) \(reason)" }
        return "\(status) \(reason): \(message)"
    }
}
