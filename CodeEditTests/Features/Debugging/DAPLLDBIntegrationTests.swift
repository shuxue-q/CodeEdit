//
//  DAPLLDBIntegrationTests.swift
//  CodeEditTests
//
//  Created by CodeEdit on 9/21/26.
//

import XCTest

@testable import CodeEdit

/// Integration tests that drive a real `lldb-dap` debug adapter through a full
/// debug session: initialize, launch, breakpoints, stack inspection, variable
/// reads, expression evaluation, and termination.
///
/// These tests are skipped when `lldb-dap` or `clang` cannot be found on the
/// host machine.
final class DAPLLDBIntegrationTests: XCTestCase {
    var tempTestDir: URL!

    override func setUp() {
        continueAfterFailure = false
        do {
            let tempDir = FileManager.default.temporaryDirectory.appending(
                path: "codeedit-dap-integration-\(UUID().uuidString)"
            )
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            tempTestDir = tempDir
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    override func tearDown() {
        if let tempTestDir {
            try? FileManager.default.removeItem(at: tempTestDir)
        }
    }

    /// Runs a complete debug session against a real `lldb-dap` process and
    /// verifies breakpoints, stack frames, variables, and evaluation.
    func testLLDBDapFullDebugSession() async throws {
        guard let lldbDap = LldbDapLocator.locate() else {
            throw XCTSkip("lldb-dap not found on this machine")
        }
        let clang = try clangPath()
        let breakpointLine = try Self.breakpointLine(in: Self.testProgramSource)
        let binary = try compileTestProgram(
            clang: clang,
            source: Self.testProgramSource,
            in: tempTestDir
        )

        let client = DAPClient(executableURL: lldbDap)
        try client.start()

        let collector = EventCollector()
        let consumer = Task {
            for await event in client.events {
                await collector.record(event)
            }
        }

        do {
            try await runDebugSession(
                client: client,
                binary: binary,
                breakpointLine: breakpointLine,
                collector: collector
            )
        } catch {
            let seen = await collector.describedEvents()
            consumer.cancel()
            await client.stop()
            XCTFail("DAP session failed: \(error). Events received: [\(seen)]")
            return
        }

        consumer.cancel()
        await client.stop()
    }

    // MARK: - Session Steps

    /// Executes the debug session against a started client, step by step.
    private func runDebugSession(
        client: DAPClient,
        binary: URL,
        breakpointLine: Int,
        collector: EventCollector
    ) async throws {
        let stopped = try await launchAndStopAtBreakpoint(
            client: client,
            binary: binary,
            breakpointLine: breakpointLine,
            collector: collector
        )
        let (threadId, topFrame) = try await inspectStoppedState(
            client: client,
            stopped: stopped,
            breakpointLine: breakpointLine,
            collector: collector
        )
        try await evaluateAndFinish(
            client: client,
            threadId: threadId,
            topFrame: topFrame,
            collector: collector
        )
    }

    /// Initializes the adapter, launches the program, sets a breakpoint on the
    /// `square(value)` call, and waits for the debuggee to stop there.
    private func launchAndStopAtBreakpoint(
        client: DAPClient,
        binary: URL,
        breakpointLine: Int,
        collector: EventCollector
    ) async throws -> DAPEvent {
        let capabilities: Capabilities? = try await withTimeout(seconds: 10) {
            try await client.send(
                "initialize",
                arguments: InitializeRequestArguments(adapterID: "CodeEditTests")
            )
        }
        XCTAssertNotNil(capabilities, "Expected capabilities in the initialize response")

        try await withTimeout(seconds: 10) {
            try await client.send(
                "launch",
                arguments: LaunchRequestArguments(
                    program: binary.path(),
                    cwd: self.tempTestDir.path(),
                    stopOnEntry: false
                )
            )
        }

        _ = try await waitForEvent(named: "initialized", collector: collector)

        let sourceURL = tempTestDir.appending(path: "main.c")
        let setBreakpoints: SetBreakpointsResponse? = try await withTimeout(seconds: 10) {
            try await client.send(
                "setBreakpoints",
                arguments: SetBreakpointsArguments(
                    source: DAPSource(name: "main.c", path: sourceURL.path()),
                    breakpoints: [DAPSourceBreakpoint(line: breakpointLine)]
                )
            )
        }
        let breakpoints = try XCTUnwrap(setBreakpoints?.breakpoints)
        XCTAssertEqual(breakpoints.count, 1)
        XCTAssertTrue(
            breakpoints.allSatisfy(\.verified),
            "Expected all breakpoints to be verified, got \(breakpoints)"
        )

        try await withTimeout(seconds: 10) {
            try await client.send("configurationDone", arguments: ConfigurationDoneArguments())
        }

        let stopped = try await waitForEvent(named: "stopped", collector: collector, timeout: 20)
        let reason = stopped.typedBody(StoppedEventBody.self)?.reason
        XCTAssertTrue(
            ["breakpoint", "entry"].contains(reason ?? ""),
            "Expected a breakpoint/entry stop, got \(reason ?? "nil")"
        )
        return stopped
    }

    /// Verifies threads, the stack of the stopped thread, and its locals.
    /// Returns the stopped thread's id and its top stack frame.
    private func inspectStoppedState(
        client: DAPClient,
        stopped: DAPEvent,
        breakpointLine: Int,
        collector: EventCollector
    ) async throws -> (threadId: Int, topFrame: DAPStackFrame) {
        let threadsResponse: ThreadsResponse? = try await withTimeout(seconds: 10) {
            try await client.send("threads")
        }
        let threads = try XCTUnwrap(threadsResponse?.threads)
        XCTAssertFalse(threads.isEmpty, "Expected at least one thread")
        let threadId = stopped.typedBody(StoppedEventBody.self)?.threadId ?? threads[0].id

        let stackTrace: StackTraceResponse? = try await withTimeout(seconds: 10) {
            try await client.send("stackTrace", arguments: StackTraceArguments(threadId: threadId))
        }
        let topFrame = try XCTUnwrap(stackTrace?.stackFrames.first)
        XCTAssertTrue(
            topFrame.source?.path?.hasSuffix("main.c") == true,
            "Expected top frame in main.c, got \(topFrame.source?.path ?? "nil")"
        )
        XCTAssertEqual(topFrame.line, breakpointLine)

        let scopes: ScopesResponse? = try await withTimeout(seconds: 10) {
            try await client.send("scopes", arguments: ScopesArguments(frameId: topFrame.id))
        }
        let scope = try XCTUnwrap(scopes?.scopes.first)
        let variables: VariablesResponse? = try await withTimeout(seconds: 10) {
            try await client.send(
                "variables",
                arguments: VariablesArguments(variablesReference: scope.variablesReference)
            )
        }
        let locals = try XCTUnwrap(variables?.variables)
        let valueVariable = locals.first { $0.name.contains("value") }
        XCTAssertNotNil(valueVariable, "Expected a 'value' variable, got \(locals.map(\.name))")
        XCTAssertTrue(
            valueVariable?.value.contains("21") == true,
            "Expected value == 21, got \(valueVariable?.value ?? "nil")"
        )

        return (threadId, topFrame)
    }

    /// Evaluates an expression in the stopped frame, then continues the
    /// debuggee until it terminates.
    private func evaluateAndFinish(
        client: DAPClient,
        threadId: Int,
        topFrame: DAPStackFrame,
        collector: EventCollector
    ) async throws {
        let evaluation: EvaluateResponse? = try await withTimeout(seconds: 10) {
            try await client.send(
                "evaluate",
                arguments: EvaluateArguments(expression: "square(2)", frameId: topFrame.id)
            )
        }
        XCTAssertTrue(
            evaluation?.result.contains("4") == true,
            "Expected square(2) == 4, got \(evaluation?.result ?? "nil")"
        )

        let _: ContinueResponse? = try await withTimeout(seconds: 10) {
            try await client.send("continue", arguments: ThreadIdArguments(threadId: threadId))
        }
        _ = try await waitForEvent(namedAnyOf: ["terminated", "exited"], collector: collector, timeout: 20)
    }

    // MARK: - Test Program

    /// The C program debugged by the integration test.
    private static let testProgramSource = """
    #include <stdio.h>

    int square(int x) { return x * x; }

    int main(void) {
        int value = 21;
        int result = square(value);
        printf("%d\\n", result);
        return 0;
    }
    """

    /// The 1-based line number of the `square(value)` call in the source.
    private static func breakpointLine(in source: String) throws -> Int {
        let lines = source.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { $0.contains("int result = square(value);") }) else {
            XCTFail("Breakpoint marker not found in test program source")
            throw DAPTestError.breakpointMarkerMissing
        }
        return index + 1
    }
}
