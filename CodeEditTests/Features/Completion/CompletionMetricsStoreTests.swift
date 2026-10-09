//
//  CompletionMetricsStoreTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
@testable import CodeEdit

@MainActor
final class CompletionMetricsStoreTests: XCTestCase {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("completion-metrics.json")
    }

    func testPercentilesUseTheNearestRank() {
        let samples = (1...100).map(Double.init)
        XCTAssertEqual(CompletionMetricsStore.percentile(samples, 0.5), 50)
        XCTAssertEqual(CompletionMetricsStore.percentile(samples, 0.95), 95)
        XCTAssertEqual(CompletionMetricsStore.percentile([7], 0.95), 7)
        XCTAssertEqual(CompletionMetricsStore.percentile([], 0.5), 0)
    }

    func testSessionCountsPopupsAcceptancesAndAverages() {
        let store = CompletionMetricsStore(fileURL: temporaryFile())
        store.recordPopup()
        store.recordPopup()
        store.recordPopup()
        store.recordAcceptance(rank: 0, keystrokes: 2)
        store.recordAcceptance(rank: 3, keystrokes: 4)

        let session = store.currentSession()
        XCTAssertEqual(session.popupCount, 3)
        XCTAssertEqual(session.acceptCount, 2)
        XCTAssertEqual(session.averageAcceptedRank, 1.5)
        XCTAssertEqual(session.averageKeystrokesToAccept, 3)
    }

    func testBackendLatencyIsRecordedUnderItsName() {
        let store = CompletionMetricsStore(fileURL: temporaryFile())
        store.recordBackendLatency(name: "ai.openAI", duration: .milliseconds(120))
        store.recordBackendLatency(name: "ai.openAI", duration: .milliseconds(480))
        store.recordProviderLatency(source: .ai, duration: .milliseconds(900))

        let latencies = store.currentSession().providerLatencies
        XCTAssertEqual(latencies["ai.openAI"]?.count, 2)
        XCTAssertEqual(latencies["ai.openAI"]?.p95Milliseconds ?? 0, 480, accuracy: 0.001)
        XCTAssertEqual(latencies["ai"]?.count, 1, "The whole-provider latency stays under the source name")
    }

    func testAveragesAreAbsentBeforeTheFirstAcceptance() {
        let session = CompletionMetricsStore(fileURL: temporaryFile()).currentSession()
        XCTAssertNil(session.averageAcceptedRank)
        XCTAssertNil(session.averageKeystrokesToAccept)
        XCTAssertTrue(session.providerLatencies.isEmpty)
    }

    func testProviderLatenciesAreSummarizedPerSource() {
        let store = CompletionMetricsStore(fileURL: temporaryFile())
        for milliseconds in 1...20 {
            store.recordProviderLatency(source: .lsp, duration: .milliseconds(milliseconds * 10))
        }
        store.recordProviderLatency(source: .word, duration: .milliseconds(3))

        let latencies = store.currentSession().providerLatencies
        XCTAssertEqual(latencies["lsp"]?.count, 20)
        XCTAssertEqual(latencies["lsp"]?.p50Milliseconds, 100)
        XCTAssertEqual(latencies["lsp"]?.p95Milliseconds, 190)
        XCTAssertEqual(latencies["word"]?.p50Milliseconds, 3)
    }

    func testLatencySamplesAreCapped() {
        let store = CompletionMetricsStore(fileURL: temporaryFile())
        for index in 0..<(CompletionMetricsStore.maximumLatencySamples + 50) {
            store.recordProviderLatency(source: .lsp, duration: .milliseconds(index))
        }
        XCTAssertEqual(
            store.currentSession().providerLatencies["lsp"]?.count,
            CompletionMetricsStore.maximumLatencySamples
        )
    }

    func testSessionsAreWrittenToAndReadFromTheFile() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let first = CompletionMetricsStore(fileURL: file, now: Date(timeIntervalSinceReferenceDate: 100))
        first.recordPopup()
        first.recordAcceptance(rank: 1, keystrokes: 1)
        first.save()
        first.recordPopup()
        first.save()

        let second = CompletionMetricsStore(fileURL: file, now: Date(timeIntervalSinceReferenceDate: 200))
        XCTAssertEqual(second.previousSessions.count, 1, "Saving twice must update the session, not add one")
        XCTAssertEqual(second.previousSessions.first?.popupCount, 2)
        XCTAssertEqual(second.previousSessions.first?.acceptCount, 1)
        second.save()

        let third = CompletionMetricsStore(fileURL: file, now: Date(timeIntervalSinceReferenceDate: 300))
        XCTAssertEqual(third.previousSessions.count, 2)
    }

    func testHistoryKeepsOnlyTheMostRecentSessions() {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        for index in 0..<(CompletionMetricsStore.maximumSessions + 5) {
            let store = CompletionMetricsStore(fileURL: file, now: Date(timeIntervalSinceReferenceDate: Double(index)))
            store.recordPopup()
            store.save()
        }
        let reloaded = CompletionMetricsStore(fileURL: file, now: Date(timeIntervalSinceReferenceDate: 1_000))
        XCTAssertEqual(reloaded.previousSessions.count, CompletionMetricsStore.maximumSessions)
    }

    func testTheDefaultLocationIsUnderApplicationSupport() {
        XCTAssertEqual(CompletionMetricsStore.defaultFileURL.lastPathComponent, "completion-metrics.json")
        XCTAssertTrue(CompletionMetricsStore.defaultFileURL.path.contains("/CodeEdit/"))
    }
}
