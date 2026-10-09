//
//  ChainScratchServerDoubles.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation
import LanguageServerProtocol
@testable import CodeEdit

/// A language server stand-in that answers completion requests on its scratch document from a table
/// keyed by the text before the cursor (for example `car.`).
@MainActor
final class FakeChainScratchServer: ChainScratchServer {
    /// `"car."` → the members the server would offer after it.
    var membersAfter: [String: [(item: CompletionItem, score: Double?)]] = [:]
    var delay: Duration = .zero
    var failure: Error?
    private(set) var updates: [String] = []
    private(set) var positions: [Position] = []
    private(set) var closeCount = 0
    private var currentText = ""

    func updateScratch(text: String) async throws {
        if let failure { throw failure }
        updates.append(text)
        currentText = text
    }

    func completeInScratch(at position: Position) async throws -> ScoredCompletionResponse {
        positions.append(position)
        try await Task.sleep(for: delay)
        let lines = currentText.components(separatedBy: "\n")
        let line = lines[Int(position.line)]
        let before = String(line.prefix(Int(position.character)))
        // The expression is the last run of identifier characters, `.` and `->` before the cursor.
        let key = String(before.reversed().prefix { $0.isLetter || $0.isNumber || "_.>-()".contains($0) }.reversed())
        var response = ScoredCompletionResponse()
        for (item, score) in membersAfter[key] ?? [] {
            response.items.append(item)
            response.scores.append(score)
        }
        return response
    }

    func closeScratch() async { closeCount += 1 }
}

/// Forwards to a fake server; every completion after the first takes five seconds.
@MainActor
final class SlowAfterFirstScratchServer: ChainScratchServer {
    let server: FakeChainScratchServer
    private var requests = 0

    init(server: FakeChainScratchServer) {
        self.server = server
    }

    func updateScratch(text: String) async throws {
        try await server.updateScratch(text: text)
    }

    func completeInScratch(at position: Position) async throws -> ScoredCompletionResponse {
        requests += 1
        if requests > 1 { try await Task.sleep(for: .seconds(5)) }
        return try await server.completeInScratch(at: position)
    }

    func closeScratch() async {
        await server.closeScratch()
    }
}
