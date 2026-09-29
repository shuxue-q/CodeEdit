//
//  DebugService.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/21/26.
//

import Foundation

extension Notification.Name {
    /// Posted when the debugger's current execution line changes or is cleared.
    ///
    /// `object` is `nil`; `userInfo` contains `"filePath"` (`String`) and
    /// `"line"` (`Int?`, 0-based, converted from DAP's 1-based lines). A `nil`
    /// line clears the highlight. Editor coordinators observe this to sync the
    /// gutter/current-line indicator.
    static let debugCurrentLineChanged = Notification.Name("DebugService.currentLineChanged")
}

/// Errors thrown by ``DebugService``.
enum DebugServiceError: Error, LocalizedError {
    /// No `lldb-dap` executable could be found on the system.
    case lldbDapNotFound
    /// The operation requires an active debug session.
    case noActiveSession
    /// The adapter answered without the expected response body.
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .lldbDapNotFound:
            return "Could not find the lldb-dap executable. Install Xcode or the LLVM toolchain."
        case .noActiveSession:
            return "There is no active debug session."
        case .invalidResponse:
            return "The debug adapter returned an unexpected response."
        }
    }
}

/// Coordinates debugging sessions: owns the ``DAPClient`` connection to
/// `lldb-dap`, tracks session state (threads, stack frames, watches, console
/// output), and bridges stopped locations into the editor.
///
/// All state and methods are isolated to the main actor; the DAP wire protocol
/// itself runs off-actor inside ``DAPClient``. Event handling and editor
/// bridging live in `DebugService+Events.swift`.
@MainActor
final class DebugService: ObservableObject {
    /// The shared debug service.
    static let shared = DebugService()

    /// High-level state of the debug session.
    enum SessionState: Equatable {
        /// No debug session.
        case inactive
        /// The adapter is launching / being configured.
        case launching
        /// The debuggee is running.
        case running
        /// The debuggee is stopped (breakpoint, step, pause, …).
        case paused
    }

    /// The current session state.
    @Published var sessionState: SessionState = .inactive
    /// Threads of the debuggee, refreshed when execution stops.
    @Published var threads: [DAPThread] = []
    /// Stack frames of the current thread, refreshed when execution stops.
    @Published var stackFrames: [DAPStackFrame] = []
    /// The stack frame selected in the UI; watch expressions evaluate against it.
    @Published var selectedFrameID: Int? {
        didSet {
            if selectedFrameID != oldValue {
                Task { await evaluateWatches() }
            }
        }
    }
    /// Accumulated debug console output.
    @Published var consoleEntries: [DebugConsoleEntry] = []
    /// Registered watch expressions, in the order they were added.
    @Published var watchExpressions: [String] = []
    /// Latest evaluation result per watch expression: a value string, or
    /// `"error: …"` text when evaluation failed.
    @Published var watchResults: [String: String] = [:]
    /// Where execution is currently stopped. The line is 1-based as reported
    /// by DAP; the ``Notification.Name/debugCurrentLineChanged`` notification
    /// carries the 0-based equivalent.
    @Published var stoppedLocation: (filePath: String, line: Int)?

    // Marked internal (not private) so the event-handling extension in
    // DebugService+Events.swift can reach them.
    weak var workspace: WorkspaceDocument?
    var client: DAPClient?
    var eventTask: Task<Void, Never>?
    var currentThreadID: Int?
    /// Bumped when a session ends so handlers that resumed after `await` can
    /// see that their session is gone and avoid writing state back.
    var sessionGeneration = 0
    /// Read by report stores on the synchronous publish of `.inactive`.
    var sessionReportStatus: ReportRecord.Status = .succeeded

    private init() {}

    // MARK: - Session Lifecycle

    /// Launches `executable` under `lldb-dap` and starts a debug session.
    ///
    /// Breakpoints from ``BreakpointStore`` are sent once the adapter signals
    /// `initialized`, followed by `configurationDone`.
    /// - Parameters:
    ///   - executable: The binary to debug.
    ///   - arguments: Command-line arguments for the debuggee.
    ///   - workingDirectory: The debuggee's working directory.
    ///   - workspace: The workspace whose editor shows stopped locations.
    /// - Throws: ``DebugServiceError/lldbDapNotFound`` when no adapter is
    ///   installed, or any ``DAPError`` from the initialize/launch handshake.
    func startDebugging(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        workspace: WorkspaceDocument
    ) async throws {
        guard sessionState == .inactive else { return }
        self.workspace = workspace
        sessionReportStatus = .succeeded
        sessionState = .launching
        // `locate()` runs the login shell. Doing that inline freezes the UI.
        let lldbDapURL = await Task.detached(priority: .userInitiated) {
            LldbDapLocator.locate()
        }.value
        guard sessionState == .launching else { return }
        guard let lldbDapURL else {
            await cleanupSession(status: .failed)
            throw DebugServiceError.lldbDapNotFound
        }

        let client = DAPClient(executableURL: lldbDapURL)
        self.client = client
        startEventLoop(client: client)
        do {
            try client.start()
            let capabilities: Capabilities? = try await client.send(
                "initialize",
                arguments: InitializeRequestArguments(adapterID: "CodeEdit")
            )
            _ = capabilities
            appendConsole(
                category: "console",
                text: "Connected to lldb-dap (\(lldbDapURL.path(percentEncoded: false)))."
            )
            try await client.send(
                "launch",
                arguments: LaunchRequestArguments(
                    program: executable.path(percentEncoded: false),
                    args: arguments,
                    cwd: workingDirectory.path(percentEncoded: false)
                )
            )
        } catch {
            recordError("Failed to start debugging", error)
            await cleanupSession(status: .failed)
            throw error
        }
        sessionState = .running
        showDebugArea()
    }

    /// Disconnects from the adapter and tears down the session.
    func stopDebugging() async {
        guard let client else { return }
        do {
            try await client.send(
                "disconnect",
                arguments: DisconnectArguments(terminateDebuggee: true)
            )
        } catch {
            recordError("Disconnect failed", error)
        }
        await client.stop()
        await cleanupSession(status: .cancelled)
    }

    // MARK: - Execution Control

    /// Resumes execution of the paused thread.
    func resume() async {
        guard sessionState == .paused, let client, let threadID = currentThreadID else { return }
        do {
            let _: ContinueResponse? = try await client.send(
                "continue",
                arguments: ThreadIdArguments(threadId: threadID)
            )
            sessionState = .running
            clearStoppedLocation()
        } catch {
            recordError("Continue failed", error)
        }
    }

    /// Pauses the running debuggee.
    ///
    /// `currentThreadID` is only known after the first stop. Before that, ask
    /// the adapter for a thread; otherwise Pause returns without sending anything.
    func pause() async {
        let generation = sessionGeneration
        guard sessionState == .running, let client else { return }
        do {
            let threadID: Int
            if let currentThreadID {
                threadID = currentThreadID
            } else {
                let response: ThreadsResponse? = try await client.send("threads")
                guard generation == sessionGeneration, sessionState == .running else { return }
                guard let resolved = response?.threads.first?.id else {
                    appendConsole(category: "error", text: "Pause failed: the debuggee has no thread to pause.")
                    return
                }
                currentThreadID = resolved
                threadID = resolved
            }
            guard generation == sessionGeneration, sessionState == .running else { return }
            try await client.send("pause", arguments: ThreadIdArguments(threadId: threadID))
        } catch {
            guard generation == sessionGeneration else { return }
            recordError("Pause failed", error)
        }
    }

    /// Steps over the current line (`next`).
    func stepOver() async {
        await step("next")
    }

    /// Steps into the current call (`stepIn`).
    func stepInto() async {
        await step("stepIn")
    }

    /// Steps out of the current function (`stepOut`).
    func stepOut() async {
        await step("stepOut")
    }

    private func step(_ command: String) async {
        guard sessionState == .paused, let client, let threadID = currentThreadID else { return }
        do {
            try await client.send(command, arguments: ThreadIdArguments(threadId: threadID))
            sessionState = .running
            clearStoppedLocation()
        } catch {
            recordError("Step failed", error)
        }
    }

    // MARK: - Variables

    /// Fetches the scopes of a stack frame.
    /// - Throws: ``DebugServiceError/noActiveSession`` when no session is active.
    func fetchScopes(frameID: Int) async throws -> [DAPScope] {
        guard let client, sessionState != .inactive else {
            throw DebugServiceError.noActiveSession
        }
        let response: ScopesResponse? = try await client.send(
            "scopes",
            arguments: ScopesArguments(frameId: frameID)
        )
        guard let response else { throw DebugServiceError.invalidResponse }
        return response.scopes
    }

    /// Fetches the children of a structured variable (or the variables of a scope).
    /// - Throws: ``DebugServiceError/noActiveSession`` when no session is active.
    func fetchVariables(reference: Int) async throws -> [DAPVariable] {
        guard let client, sessionState != .inactive else {
            throw DebugServiceError.noActiveSession
        }
        let response: VariablesResponse? = try await client.send(
            "variables",
            arguments: VariablesArguments(variablesReference: reference)
        )
        guard let response else { throw DebugServiceError.invalidResponse }
        return response.variables
    }

    // MARK: - Watch Expressions

    /// Adds a watch expression and evaluates it if execution is paused.
    func addWatch(_ expression: String) {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !watchExpressions.contains(trimmed) else { return }
        watchExpressions.append(trimmed)
        Task { await evaluateWatches() }
    }

    /// Removes a watch expression and its cached result.
    func removeWatch(_ expression: String) {
        watchExpressions.removeAll { $0 == expression }
        watchResults.removeValue(forKey: expression)
    }

    /// Evaluates every watch expression against the selected stack frame.
    /// Does nothing unless the debuggee is paused.
    func evaluateWatches() async {
        let generation = sessionGeneration
        guard let client, sessionState == .paused, !watchExpressions.isEmpty else { return }
        let frameID = selectedFrameID
        var results: [String: String] = [:]
        for expression in watchExpressions {
            guard generation == sessionGeneration else { return }
            do {
                let response: EvaluateResponse? = try await client.send(
                    "evaluate",
                    arguments: EvaluateArguments(expression: expression, frameId: frameID)
                )
                results[expression] = response?.result ?? "<no result>"
            } catch {
                results[expression] = "error: \(describe(error))"
            }
        }
        guard generation == sessionGeneration, sessionState == .paused else { return }
        watchResults = results
    }

    // MARK: - Breakpoint Sync

    /// Resends the full breakpoint set for `filePath` to the adapter.
    ///
    /// Does nothing when no session is active; breakpoints are otherwise sent
    /// during the launch handshake. Lines are converted from the store's
    /// 0-based indexes to DAP's 1-based lines.
    func syncBreakpoints(filePath: String) async {
        guard let client, sessionState != .inactive else { return }
        await sendBreakpoints(
            client: client,
            filePath: filePath,
            lines: BreakpointStore.shared.lines(for: filePath)
        )
    }

    func sendBreakpoints(client: DAPClient, filePath: String, lines: Set<Int>) async {
        let effectiveLines = BreakpointStore.shared.isEnabled ? lines : []
        do {
            let response: SetBreakpointsResponse? = try await client.send(
                "setBreakpoints",
                arguments: SetBreakpointsArguments(
                    source: DAPSource(
                        name: URL(fileURLWithPath: filePath).lastPathComponent,
                        path: filePath
                    ),
                    breakpoints: effectiveLines.sorted().map { DAPSourceBreakpoint(line: $0 + 1) }
                )
            )
            let failed = response?.breakpoints.filter { !$0.verified } ?? []
            if let message = failed.compactMap(\.message).first {
                appendConsole(
                    category: "error",
                    text: "Breakpoint in \(filePath) not verified: \(message)"
                )
            }
        } catch {
            recordError("Failed to set breakpoints in \(filePath)", error)
        }
    }
}
