//
//  DebugService+Events.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/21/26.
//

import Foundation
import CodeEditSourceEditor

// Event loop, session teardown, and editor/UI bridging for `DebugService`.
// Split out to keep DebugService.swift under the type/file length limits.
extension DebugService {
    // MARK: - Event Loop

    /// Consumes adapter events for the lifetime of the session.
    ///
    /// The task inherits the main actor from the enclosing type, so handlers
    /// mutate published state directly. Events are buffered by the client's
    /// `AsyncStream`, so awaiting requests (e.g. `threads`) inside the loop
    /// cannot deadlock the read path.
    func startEventLoop(client: DAPClient) {
        eventTask = Task { [weak self] in
            for await event in client.events {
                guard let self, !Task.isCancelled else { break }
                await self.handle(event: event)
            }
        }
    }

    func handle(event: DAPEvent) async {
        switch event.event {
        case "initialized":
            await handleInitialized()
        case "stopped":
            await handleStopped(body: event.typedBody(StoppedEventBody.self))
        case "continued":
            sessionState = .running
            clearStoppedLocation()
        case "output":
            if let body = event.typedBody(OutputEventBody.self) {
                appendConsole(category: body.category ?? "console", text: body.output)
            }
        case "terminated":
            appendConsole(category: "console", text: "Debug session terminated.")
            await cleanupSession()
        case "exited":
            if let exitCode = event.typedBody(ExitedEventBody.self)?.exitCode {
                appendConsole(category: "console", text: "Process exited with code \(exitCode).")
                if exitCode != 0 {
                    sessionReportStatus = .failed
                }
            }
            await cleanupSession()
        default:
            break
        }
    }

    /// The adapter is ready to receive configuration. Per DAP this event may
    /// arrive before or after the `launch` response, so breakpoint sync and
    /// `configurationDone` are driven by the event itself, not by ordering
    /// assumptions in `startDebugging(executable:arguments:workingDirectory:workspace:)`.
    private func handleInitialized() async {
        let generation = sessionGeneration
        guard let client else { return }
        for (filePath, lines) in BreakpointStore.shared.breakpoints where !lines.isEmpty {
            guard generation == sessionGeneration else { return }
            await sendBreakpoints(client: client, filePath: filePath, lines: lines)
        }
        guard generation == sessionGeneration else { return }
        do {
            try await client.send("configurationDone", arguments: ConfigurationDoneArguments())
        } catch {
            guard generation == sessionGeneration else { return }
            recordError("configurationDone failed", error)
        }
    }

    private func handleStopped(body: StoppedEventBody?) async {
        let generation = sessionGeneration
        guard let client else { return }
        sessionState = .paused
        do {
            let threadsResponse: ThreadsResponse? = try await client.send("threads")
            guard generation == sessionGeneration else { return }
            threads = threadsResponse?.threads ?? []
            let threadID = body?.threadId ?? threads.first?.id
            currentThreadID = threadID
            guard let threadID else { return }

            let stackResponse: StackTraceResponse? = try await client.send(
                "stackTrace",
                arguments: StackTraceArguments(threadId: threadID)
            )
            guard generation == sessionGeneration else { return }
            stackFrames = stackResponse?.stackFrames ?? []
            selectedFrameID = stackFrames.first?.id

            if let frame = stackFrames.first, let path = frame.source?.path {
                let previousPath = stoppedLocation?.filePath
                stoppedLocation = (filePath: path, line: frame.line)
                if let previousPath, !DebugFilePath.sameFile(previousPath, path) {
                    postCurrentLine(filePath: previousPath, line: nil)
                }
                revealInEditor(filePath: path, line: frame.line, column: frame.column)
                postCurrentLine(filePath: path, line: frame.line - 1)
            } else {
                clearStoppedLocation()
            }
            guard generation == sessionGeneration else { return }
            showDebugArea()
            await evaluateWatches()
        } catch {
            guard generation == sessionGeneration else { return }
            recordError("Failed to inspect stopped state", error)
        }
    }

    // MARK: - Cleanup

    /// Tears down all session state. Idempotent; safe to call from the event
    /// loop (`terminated`/`exited`) and from `stopDebugging()`.
    ///
    /// `status` is the outcome recorded for this session. When omitted, the
    /// value already stored (for example a non-zero exit code) is kept.
    /// The transition to `.inactive` is published while `workspace` is still
    /// set, so report stores can see who owned the session.
    func cleanupSession(status: ReportRecord.Status? = nil) async {
        sessionGeneration += 1
        if let status {
            sessionReportStatus = status
        }
        let shouldPublishEnd = sessionState != .inactive
        eventTask?.cancel()
        eventTask = nil
        // Tolerates repeated calls and a dead process.
        await client?.stop()
        client = nil
        currentThreadID = nil
        threads = []
        stackFrames = []
        selectedFrameID = nil
        watchResults = [:]
        clearStoppedLocation()
        if shouldPublishEnd {
            sessionState = .inactive
        }
        workspace = nil
        sessionReportStatus = .succeeded
    }

    // MARK: - Editor & UI Bridging

    /// Opens the stopped location in the workspace editor, mirroring
    /// `WorkspaceDiagnostics.open(_:workspace:)`.
    private func revealInEditor(filePath: String, line: Int, column: Int) {
        guard let workspace,
              let file = workspace.workspaceFileManager?.getFile(filePath, createIfNotFound: true)
        else {
            return
        }
        workspace.editorManager?.openTab(item: file)
        workspace.editorManager?.activeEditor.selectedTab?.cursorPositions = [
            CursorPosition(line: max(line, 1), column: max(column, 1))
        ]
    }

    /// Expands the utility area on the debug tab so console/state is visible.
    func showDebugArea() {
        guard let utilityArea = workspace?.utilityAreaModel else { return }
        utilityArea.isCollapsed = false
        utilityArea.selectedTab = .debugger
    }

    // MARK: - Current Line Notification

    /// Posts `Notification.Name.debugCurrentLineChanged`. `line` is 0-based.
    func postCurrentLine(filePath: String, line: Int?) {
        NotificationCenter.default.post(
            name: .debugCurrentLineChanged,
            object: nil,
            userInfo: ["filePath": filePath, "line": line as Any]
        )
    }

    func clearStoppedLocation() {
        let previousPath = stoppedLocation?.filePath
        stoppedLocation = nil
        postCurrentLine(filePath: previousPath ?? "", line: nil)
    }

    // MARK: - Console

    func appendConsole(category: String, text: String) {
        consoleEntries.append(DebugConsoleEntry(category: category, text: text))
    }

    /// Records a failure to the console instead of throwing, so the UI never
    /// crashes on adapter errors from user-driven control actions.
    func recordError(_ prefix: String, _ error: Error) {
        appendConsole(category: "error", text: "\(prefix): \(describe(error))")
    }

    func describe(_ error: Error) -> String {
        if case let DAPError.requestFailed(command, message) = error {
            if let message, !message.isEmpty {
                return "\(command): \(message)"
            }
            return "\(command) failed"
        }
        return error.localizedDescription
    }
}
