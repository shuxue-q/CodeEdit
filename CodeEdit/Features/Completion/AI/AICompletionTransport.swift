//
//  AICompletionTransport.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// What one exchange with a backend's server produced.
struct AICompletionExchange {
    /// The response body.
    let data: Data
    /// The response.
    let response: HTTPURLResponse
    /// The backend whose wording of the request the response answers: the one that was asked to send it, or
    /// its alternative when the server refused the first wording.
    let backend: any AICompletionBackend
    /// Whether ``backend`` is the alternative, not the backend that was asked.
    let usedAlternative: Bool
}

/// Sends a request through a backend and, when the server refuses the way the request is worded, once more
/// worded the way the backend's alternative words it.
enum AICompletionTransport {
    /// Sends `request` to the server `backend` talks to.
    /// - Parameters:
    ///   - request: What to ask.
    ///   - backend: Builds the HTTP request and offers the alternative wording.
    ///   - configuration: Model, base URL and key.
    ///   - session: The session the HTTP request goes through.
    ///   - timeout: Overrides the HTTP request's timeout, if given.
    /// - Throws: ``AIBackendError/invalidConfiguration(_:)`` when no request can be formed, and the
    ///   session's errors.
    static func send(
        _ request: AICompletionRequest,
        backend: any AICompletionBackend,
        configuration: AIBackendConfiguration,
        session: URLSession,
        timeout: TimeInterval? = nil
    ) async throws -> AICompletionExchange {
        let (data, response) = try await exchange(request, backend, configuration, session, timeout)
        guard !(200..<300).contains(response.statusCode),
              let alternative = backend.alternative(afterRejection: data, response: response) else {
            return AICompletionExchange(data: data, response: response, backend: backend, usedAlternative: false)
        }
        try Task.checkCancellation()
        let (retryData, retryResponse) = try await exchange(request, alternative, configuration, session, timeout)
        return AICompletionExchange(
            data: retryData, response: retryResponse, backend: alternative, usedAlternative: true
        )
    }

    private static func exchange(
        _ request: AICompletionRequest,
        _ backend: any AICompletionBackend,
        _ configuration: AIBackendConfiguration,
        _ session: URLSession,
        _ timeout: TimeInterval?
    ) async throws -> (Data, HTTPURLResponse) {
        var urlRequest = try backend.makeRequest(request, configuration: configuration)
        if let timeout { urlRequest.timeoutInterval = timeout }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw AIBackendError.malformedResponse }
        return (data, http)
    }
}
