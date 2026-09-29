//
//  DAPTestSupport.swift
//  CodeEditTests
//
//  Created by CodeEdit on 9/21/26.
//

import XCTest

@testable import CodeEdit

/// Errors thrown by the DAP integration test helpers.
enum DAPTestError: Error {
    /// An operation did not finish within its allotted time.
    case timedOut(String)
    /// The test C program failed to compile.
    case compilationFailed
    /// The expected marker line was not found in the test program source.
    case breakpointMarkerMissing
}

/// Collects every event emitted by a `DAPClient` so tests can wait for a named
/// event without racing, and can dump the event history on failure.
actor EventCollector {
    private var events: [DAPEvent] = []
    private var cursor = 0

    /// Appends an event received from the client's event stream.
    func record(_ event: DAPEvent) {
        events.append(event)
    }

    /// Returns and consumes the oldest unconsumed event whose name matches.
    func take(namedAnyOf names: [String]) -> DAPEvent? {
        guard cursor < events.count,
              let index = events[cursor...].firstIndex(where: { names.contains($0.event) }) else {
            return nil
        }
        cursor = index + 1
        return events[index]
    }

    /// A compact `seq:name` listing of every event received so far.
    func describedEvents() -> String {
        events.map { "\($0.seq):\($0.event)" }.joined(separator: ", ")
    }
}

/// Runs an async operation, throwing ``DAPTestError/timedOut(_:)`` if it does
/// not finish within `seconds`.
func withTimeout<T: Sendable>(
    seconds: UInt64,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw DAPTestError.timedOut("operation")
        }
        guard let result = try await group.next() else {
            throw DAPTestError.timedOut("empty task group")
        }
        group.cancelAll()
        return result
    }
}

/// Polls the collector until an event with the given name arrives.
func waitForEvent(
    named name: String,
    collector: EventCollector,
    timeout: UInt64 = 15
) async throws -> DAPEvent {
    try await waitForEvent(namedAnyOf: [name], collector: collector, timeout: timeout)
}

/// Polls the collector until an event matching any of the names arrives,
/// failing after `timeout` seconds with the received event history.
func waitForEvent(
    namedAnyOf names: [String],
    collector: EventCollector,
    timeout: UInt64
) async throws -> DAPEvent {
    let deadline = ContinuousClock.now + .seconds(Int64(timeout))
    while ContinuousClock.now < deadline {
        try Task.checkCancellation()
        if let event = await collector.take(namedAnyOf: names) {
            return event
        }
        try await Task.sleep(for: .milliseconds(50))
    }
    let seen = await collector.describedEvents()
    XCTFail("Timed out waiting for \(names) event. Events received: [\(seen)]")
    throw DAPTestError.timedOut(names.joined(separator: "|"))
}

/// Locates a `clang` compiler, skipping the test when none is available.
func clangPath() throws -> String {
    if FileManager.default.isExecutableFile(atPath: "/usr/bin/clang") {
        return "/usr/bin/clang"
    }
    if let path = LanguageServerDetector.locateExecutables(["clang"])["clang"],
       FileManager.default.isExecutableFile(atPath: path) {
        return path
    }
    throw XCTSkip("clang not found on this machine")
}

/// Writes `source` to `main.c` in `directory` and compiles it to `main` with
/// debug info and no optimizations, returning the binary's URL.
func compileTestProgram(clang: String, source: String, in directory: URL) throws -> URL {
    let sourceURL = directory.appending(path: "main.c")
    try source.write(to: sourceURL, atomically: true, encoding: .utf8)
    let binaryURL = directory.appending(path: "main")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: clang)
    process.arguments = ["-g", "-O0", sourceURL.path(), "-o", binaryURL.path()]
    let stderr = Pipe()
    process.standardError = stderr
    try process.run()
    // Read before waiting so a full pipe buffer cannot deadlock the child.
    let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let text = String(data: stderrData, encoding: .utf8) ?? ""
        XCTFail("clang exited with status \(process.terminationStatus): \(text)")
        throw DAPTestError.compilationFailed
    }
    return binaryURL
}
