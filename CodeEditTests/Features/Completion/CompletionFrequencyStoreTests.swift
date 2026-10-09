//
//  CompletionFrequencyStoreTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import XCTest
@testable import CodeEdit

final class CompletionFrequencyStoreTests: XCTestCase {
    func testInMemoryStoreRecordsAcceptancesPerLanguage() {
        let store = InMemoryCompletionFrequencyStore()
        store.recordAcceptance(label: "printf", languageId: "c")
        store.recordAcceptance(label: "printf", languageId: "c")
        store.recordAcceptance(label: "printf", languageId: "cpp")

        XCTAssertEqual(store.frequencies(for: "c")["printf"], 2)
        XCTAssertEqual(store.frequencies(for: "cpp")["printf"], 1)
        XCTAssertEqual(store.frequencies(for: "swift")["printf"], nil)
    }

    func testDiskBackedStoreRoundTripsThroughAFile() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = CompletionFrequencyStore(fileURL: fileURL)
        store.recordAcceptance(label: "vector", languageId: "cpp")

        let expectation = expectation(description: "frequency file written")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { expectation.fulfill() }
        wait(for: [expectation], timeout: 4)

        let reloaded = CompletionFrequencyStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.frequencies(for: "cpp")["vector"], 1)
    }

    func testDecayScalesDownCountsOnceTheTotalIsLarge() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = CompletionFrequencyStore(fileURL: fileURL)
        for _ in 0..<1_100 {
            store.recordAcceptance(label: "x", languageId: "c")
        }
        let count = store.frequencies(for: "c")["x"] ?? 0
        XCTAssertLessThan(count, 1_100, "Counts must decay once the language's total crosses the threshold")
    }

    func testNormalizedLabelsAreUsedAsKeys() {
        let store = InMemoryCompletionFrequencyStore()
        store.recordAcceptance(label: "•printf", languageId: "c")
        XCTAssertEqual(store.frequencies(for: "c")["printf"], 1)
    }
}

// MARK: - Per-intent statistics and recency

extension CompletionFrequencyStoreTests {
    private func temporaryFiles() -> (frequency: URL, statistics: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            directory.appendingPathComponent("completion-frequency.json"),
            directory.appendingPathComponent("completion-statistics.json")
        )
    }

    func testAcceptancesAreCountedPerIntentAndPerLanguage() {
        let store = InMemoryCompletionFrequencyStore()
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        store.recordAcceptance(label: "size", languageId: "cpp", intent: .memberAccess, at: date)
        store.recordAcceptance(label: "size", languageId: "cpp", intent: .expression, at: date)

        let member = store.statistics(languageId: "cpp", intent: .memberAccess)
        XCTAssertEqual(member.intentFrequencies["size"], 1)
        XCTAssertEqual(member.languageFrequencies["size"], 2)
        XCTAssertEqual(member.lastAccepted["size"], date)
        XCTAssertNil(store.statistics(languageId: "cpp", intent: .statement).intentFrequencies["size"])
    }

    func testStatisticsRoundTripThroughTheirFileAndTheOldFileIsStillWritten() {
        let files = temporaryFiles()
        defer { try? FileManager.default.removeItem(at: files.frequency.deletingLastPathComponent()) }
        let date = Date(timeIntervalSinceReferenceDate: 5_000)
        let store = CompletionFrequencyStore(fileURL: files.frequency, statisticsURL: files.statistics)
        store.recordAcceptance(label: "size", languageId: "cpp", intent: .memberAccess, at: date)

        let written = expectation(description: "files written")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { written.fulfill() }
        wait(for: [written], timeout: 4)

        XCTAssertTrue(FileManager.default.fileExists(atPath: files.statistics.path))
        let legacy = try? JSONDecoder().decode(
            [String: [String: Int]].self,
            from: Data(contentsOf: files.frequency)
        )
        XCTAssertEqual(legacy?["cpp"]?["size"], 1, "The per-language file keeps its original format")

        let reloaded = CompletionFrequencyStore(fileURL: files.frequency, statisticsURL: files.statistics)
        let stats = reloaded.statistics(languageId: "cpp", intent: .memberAccess)
        XCTAssertEqual(stats.intentFrequencies["size"], 1)
        XCTAssertEqual(stats.lastAccepted["size"], date)
    }

    func testAnOldFormatFileStillLoadsAsTheLanguageFallback() throws {
        let files = temporaryFiles()
        defer { try? FileManager.default.removeItem(at: files.frequency.deletingLastPathComponent()) }
        try Data(#"{"cpp":{"printf":7}}"#.utf8).write(to: files.frequency)

        let store = CompletionFrequencyStore(fileURL: files.frequency, statisticsURL: files.statistics)
        let stats = store.statistics(languageId: "cpp", intent: .expression)
        XCTAssertEqual(stats.languageFrequencies["printf"], 7)
        XCTAssertTrue(stats.intentFrequencies.isEmpty)
        XCTAssertEqual(store.frequencies(for: "cpp")["printf"], 7)
    }

    func testTheLegacyRecordingMethodStillWorksWithoutAnIntent() {
        let store = CompletionFrequencyStore(
            fileURL: temporaryFiles().frequency,
            statisticsURL: temporaryFiles().statistics
        )
        store.recordAcceptance(label: "printf", languageId: "c")
        XCTAssertEqual(store.frequencies(for: "c")["printf"], 1)
        XCTAssertTrue(store.statistics(languageId: "c", intent: .expression).intentFrequencies.isEmpty)
    }

    func testIntentCountsDecayOnceTheirTotalIsLarge() {
        let files = temporaryFiles()
        defer { try? FileManager.default.removeItem(at: files.frequency.deletingLastPathComponent()) }
        let store = CompletionFrequencyStore(fileURL: files.frequency, statisticsURL: files.statistics)
        for _ in 0..<1_100 {
            store.recordAcceptance(label: "x", languageId: "c", intent: .expression, at: Date())
        }
        let count = store.statistics(languageId: "c", intent: .expression).intentFrequencies["x"] ?? 0
        XCTAssertLessThan(count, 1_100)
        XCTAssertGreaterThan(count, 0)
    }

    func testStatisticsFileNameIsDerivedNextToTheFrequencyFile() {
        let url = URL(fileURLWithPath: "/tmp/dir/completion-frequency.json")
        XCTAssertEqual(
            CompletionFrequencyStore.siblingStatisticsURL(for: url).lastPathComponent,
            "completion-statistics.json"
        )
        let custom = URL(fileURLWithPath: "/tmp/dir/abc.json")
        XCTAssertEqual(
            CompletionFrequencyStore.siblingStatisticsURL(for: custom).lastPathComponent,
            "abc-statistics.json"
        )
    }
}

// MARK: - Receiver types

extension CompletionFrequencyStoreTests {
    private func accept(
        _ store: CompletionFrequencyStoring,
        _ label: String,
        receiver: String?,
        at date: Date = Date(timeIntervalSinceReferenceDate: 1_000)
    ) {
        store.recordAcceptance(
            label: label, languageId: "cpp", intent: .memberAccess, receiverType: receiver, at: date
        )
    }

    func testAMemberAcceptedOnAReceiverTypeCountsOnlyForThatType() {
        let store = InMemoryCompletionFrequencyStore()
        accept(store, "push_back", receiver: "std::vector<int>")
        accept(store, "push_back", receiver: "std::vector<int>")

        let sameType = store.statistics(languageId: "cpp", intent: .memberAccess, receiverType: "std::vector<int>")
        XCTAssertEqual(sameType.receiverFrequencies["push_back"], 2)
        XCTAssertEqual(sameType.receiverLastAccepted["push_back"], Date(timeIntervalSinceReferenceDate: 1_000))

        let otherType = store.statistics(languageId: "cpp", intent: .memberAccess, receiverType: "std::string")
        XCTAssertTrue(otherType.receiverFrequencies.isEmpty)
        XCTAssertTrue(otherType.intentFrequencies.isEmpty, "A receiver-keyed acceptance must not leak into the intent")
        XCTAssertTrue(otherType.languageFrequencies.isEmpty, "…nor into the language table")

        let unknown = store.statistics(languageId: "cpp", intent: .memberAccess, receiverType: nil)
        XCTAssertTrue(unknown.receiverFrequencies.isEmpty)
    }

    func testWithoutAReceiverTypeTheAcceptanceIsPerIntentAsBefore() {
        let store = InMemoryCompletionFrequencyStore()
        accept(store, "size", receiver: nil)
        let stats = store.statistics(languageId: "cpp", intent: .memberAccess, receiverType: "std::string")
        XCTAssertEqual(stats.intentFrequencies["size"], 1)
        XCTAssertTrue(stats.receiverFrequencies.isEmpty)
    }

    func testReceiverStatisticsRoundTripThroughTheFile() {
        let files = temporaryFiles()
        defer { try? FileManager.default.removeItem(at: files.frequency.deletingLastPathComponent()) }
        let date = Date(timeIntervalSinceReferenceDate: 7_000)
        let store = CompletionFrequencyStore(fileURL: files.frequency, statisticsURL: files.statistics)
        accept(store, "push_back", receiver: "std::vector<int>", at: date)

        let written = expectation(description: "files written")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { written.fulfill() }
        wait(for: [written], timeout: 4)

        let reloaded = CompletionFrequencyStore(fileURL: files.frequency, statisticsURL: files.statistics)
        let stats = reloaded.statistics(languageId: "cpp", intent: .memberAccess, receiverType: "std::vector<int>")
        XCTAssertEqual(stats.receiverFrequencies["push_back"], 1)
        XCTAssertEqual(stats.receiverLastAccepted["push_back"], date)
        XCTAssertTrue(
            reloaded.statistics(languageId: "cpp", intent: .memberAccess, receiverType: "std::string")
                .receiverFrequencies.isEmpty
        )
    }

    func testAStatisticsFileWithoutReceiversStillLoads() throws {
        let files = temporaryFiles()
        defer { try? FileManager.default.removeItem(at: files.frequency.deletingLastPathComponent()) }
        let json = #"{"version":1,"entries":{"cpp":{"memberAccess":{"size":{"count":4,"last":100}}}}}"#
        try Data(json.utf8).write(to: files.statistics)

        let store = CompletionFrequencyStore(fileURL: files.frequency, statisticsURL: files.statistics)
        let stats = store.statistics(languageId: "cpp", intent: .memberAccess, receiverType: "std::string")
        XCTAssertEqual(stats.intentFrequencies["size"], 4, "Entries from before receiver types keep loading")
        XCTAssertTrue(stats.receiverFrequencies.isEmpty)
    }

    func testAFileWithoutReceiversIsWrittenWithoutTheKey() throws {
        let files = temporaryFiles()
        defer { try? FileManager.default.removeItem(at: files.frequency.deletingLastPathComponent()) }
        let store = CompletionFrequencyStore(fileURL: files.frequency, statisticsURL: files.statistics)
        store.recordAcceptance(
            label: "size", languageId: "cpp", intent: .memberAccess, at: Date(timeIntervalSinceReferenceDate: 1)
        )
        let written = expectation(description: "files written")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { written.fulfill() }
        wait(for: [written], timeout: 4)
        let text = try String(contentsOf: files.statistics, encoding: .utf8)
        XCTAssertFalse(text.contains("receivers"), "Older readers should see exactly the old format: \(text)")
    }

    func testReceiverCountsDecayOnceTheirTotalIsLarge() {
        let files = temporaryFiles()
        defer { try? FileManager.default.removeItem(at: files.frequency.deletingLastPathComponent()) }
        let store = CompletionFrequencyStore(fileURL: files.frequency, statisticsURL: files.statistics)
        for _ in 0..<1_100 {
            accept(store, "x", receiver: "Widget")
        }
        let count = store.statistics(languageId: "cpp", intent: .memberAccess, receiverType: "Widget")
            .receiverFrequencies["x"] ?? 0
        XCTAssertLessThan(count, 1_100)
        XCTAssertGreaterThan(count, 0)
    }

    func testOnlyTheMostRecentlyUsedReceiverTypesAreKept() {
        let files = temporaryFiles()
        defer { try? FileManager.default.removeItem(at: files.frequency.deletingLastPathComponent()) }
        let store = CompletionFrequencyStore(fileURL: files.frequency, statisticsURL: files.statistics)
        let limit = CompletionFrequencyStore.maximumReceiverTypes
        for index in 0...limit {
            accept(store, "m", receiver: "Type\(index)", at: Date(timeIntervalSinceReferenceDate: Double(index)))
        }
        let oldest = store.statistics(languageId: "cpp", intent: .memberAccess, receiverType: "Type0")
        let newest = store.statistics(languageId: "cpp", intent: .memberAccess, receiverType: "Type\(limit)")
        XCTAssertTrue(oldest.receiverFrequencies.isEmpty, "The least recently used type is forgotten first")
        XCTAssertEqual(newest.receiverFrequencies["m"], 1)
    }

    func testStoresWithoutReceiverSupportFallBackToIntentStatistics() {
        final class LegacyStore: CompletionFrequencyStoring {
            var intentAcceptances = 0
            func frequencies(for languageId: String) -> [String: Int] { [:] }
            func recordAcceptance(label: String, languageId: String) { }
            func recordAcceptance(label: String, languageId: String, intent: CompletionIntent, at date: Date) {
                intentAcceptances += 1
            }
        }
        let store = LegacyStore()
        accept(store, "size", receiver: "std::string")
        XCTAssertEqual(store.intentAcceptances, 1)
        XCTAssertTrue(
            store.statistics(languageId: "cpp", intent: .memberAccess, receiverType: "std::string")
                .receiverFrequencies.isEmpty
        )
    }
}
