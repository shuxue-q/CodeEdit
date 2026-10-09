//
//  AIStubURLProtocol.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// Routes every request of a session through a handler set per test, instead of touching the network.
/// Throwing from the handler fails the request with that error.
final class AIStubURLProtocol: URLProtocol {
    /// Answers a request. Reset to `nil` in `tearDown`/`defer`.
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    /// A session whose requests all go to ``handler``.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

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
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() { }
}
