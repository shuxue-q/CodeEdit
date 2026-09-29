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
