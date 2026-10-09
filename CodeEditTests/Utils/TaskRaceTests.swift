//
//  TaskRaceTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
@testable import CodeEdit

final class TaskRaceTests: XCTestCase {
    func testReturnsTheValueOfATaskThatFinishesInTime() async {
        let task = Task { () -> Int in
            try? await Task.sleep(for: .milliseconds(20))
            return 42
        }
        let value = await awaitValue(of: task, upTo: .seconds(2))
        XCTAssertEqual(value, 42)
    }

    func testReturnsNilOnTimeoutEvenWhenTheTaskIgnoresCancellation() async {
        // Blocks without ever checking for cancellation, like a request that cannot be cancelled.
        let task = Task.detached { () -> Int in
            Thread.sleep(forTimeInterval: 1.0)
            return 1
        }
        let start = ContinuousClock.now
        let value = await awaitValue(of: task, upTo: .milliseconds(100))
        XCTAssertNil(value)
        XCTAssertLessThan(ContinuousClock.now - start, .milliseconds(700))
    }
}
