//
//  CEActiveTask.swift
//  CodeEditTests
//
//  Created by Tommy Ludwig on 24.06.24.
//

import SwiftUI
import Combine
import SwiftTerm

/// Stores the state of a task once it's executed
class CEActiveTask: ObservableObject, Identifiable, Hashable {
    /// The current progress of the task.
    @Published var output: CEActiveTaskTerminalView?

    var hasOutputBeenConfigured: Bool = false

    /// The status of the task.
    @Published private(set) var status: CETaskStatus = .notRunning

    /// The name of the associated task.
    @ObservedObject var task: CETask

    /// Prevents tasks overwriting each other.
    /// Say a user cancels one task, then runs it immediately, the cancel message should show and then the
    /// starting message should show. If we don't add this modifier the starting message will be deleted.
    var activeTaskID: UUID = UUID()

    var taskId: String {
        task.id.uuidString + "-" + activeTaskID.uuidString
    }

    var workspaceURL: URL?

    /// Set when the user asked to cancel the current run (via ``terminate()`` or
    /// ``interrupt()``). A cancelled run reports ``CETaskStatus/notRunning`` when the
    /// process ends, even if the shell reports the killed command's signal as a regular
    /// exit code (shells exit with 128 + signal number when their foreground job dies).
    private var cancellationRequested = false

    private var cancellables = Set<AnyCancellable>()

    init(task: CETask) {
        self.task = task

        self.task.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    @MainActor
    func run(workspaceURL: URL?, shell: Shell? = nil) {
        self.workspaceURL = workspaceURL
        self.activeTaskID = UUID() // generate a new ID for this run
        self.cancellationRequested = false

        createStatusTaskNotification()
        updateTaskStatus(to: .running)

        let view = output ?? CEActiveTaskTerminalView(activeTask: self)
        view.startProcess(workspaceURL: workspaceURL, shell: shell)

        output = view
    }

    @MainActor
    func handleProcessFinished(terminationStatus: Int32) {
        // SwiftTerm forwards the raw `waitpid(2)` status word, not a plain exit code:
        // when the low 7 bits are zero the process exited on its own and bits 8-15 hold
        // the exit code; otherwise the low 7 bits hold the signal that killed it. A low
        // byte of 0x7f means the process was stopped by the signal in bits 8-15.
        let terminatingSignal = terminationStatus & 0x7f
        let wasStopped = (terminationStatus & 0xff) == 0x7f
        let exitCode = (terminationStatus >> 8) & 0xff

        if wasStopped {
            updateTaskStatus(to: .stopped)
        } else if cancellationRequested || terminatingSignal == SIGINT || terminatingSignal == SIGTERM {
            output?.newline()
            output?.sendOutputMessage("\(task.name) cancelled.")
            output?.newline()

            updateTaskStatus(to: .notRunning)
            updateTaskNotification(
                title: "\(task.name) cancelled",
                message: "",
                isLoading: false
            )
        } else if terminatingSignal == 0 && exitCode == 0 {
            output?.newline()
            output?.sendOutputMessage("Finished running \(task.name).")
            output?.newline()

            updateTaskStatus(to: .finished)
            updateTaskNotification(
                title: "Finished Running \(task.name)",
                message: "",
                isLoading: false
            )
        } else {
            output?.newline()
            output?.sendOutputMessage("Failed to run \(task.name)")
            output?.newline()

            updateTaskStatus(to: .failed)
            updateTaskNotification(
                title: "Failed Running \(task.name)",
                message: "",
                isLoading: false
            )
        }

        cancellationRequested = false
        deleteStatusTaskNotification()
    }

    @MainActor
    func suspend() {
        guard output?.runningPID() != nil, status == .running else { return }
        signalTask(SIGSTOP)
        updateTaskStatus(to: .stopped)
    }

    @MainActor
    func resume() {
        guard output?.runningPID() != nil, status == .stopped else { return }
        signalTask(SIGCONT)
        updateTaskStatus(to: .running)
    }

    func terminate() {
        guard let shellPID = output?.runningPID() else { return }
        cancellationRequested = true
        signalTask(SIGTERM)
        // A stopped process does not act on a pending SIGTERM until it is continued.
        signalTask(SIGCONT)
        // Interactive shells ignore SIGTERM; SIGHUP takes the shell down with its job so
        // the session does not outlive the task.
        kill(shellPID, SIGHUP)
    }

    func interrupt() {
        guard output?.runningPID() != nil else { return }
        cancellationRequested = true
        signalTask(SIGINT)
    }

    /// Sends a signal to the process group running the task's command.
    ///
    /// SwiftTerm spawns the shell via `forkpty`, so the shell is a session and process
    /// group leader — but interactive shells use job control and place every command they
    /// run into its own process group. Signaling the shell's process ID (or its own
    /// process group) therefore never reaches the command. The pseudo-terminal's
    /// foreground process group does — it is what Ctrl+C targets — so that group is
    /// signaled instead, falling back to the shell's group when no foreground job exists.
    /// - Parameter signal: The signal to send, e.g. `SIGTERM`.
    private func signalTask(_ signal: Int32) {
        guard let shellPID = output?.runningPID() else { return }
        killpg(foregroundProcessGroup(of: shellPID) ?? shellPID, signal)
    }

    /// The foreground process group of the shell's controlling terminal, the `killpg`
    /// equivalent of `tcgetpgrp` without requiring the pseudo-terminal's file descriptor.
    /// - Parameter shellPID: The shell's process identifier.
    /// - Returns: The foreground process group, or `nil` when it cannot be determined.
    private func foregroundProcessGroup(of shellPID: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, shellPID]
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        return info.kp_eproc.e_tpgid > 0 ? info.kp_eproc.e_tpgid : nil
    }

    func waitForExit() {
        if let shellPID = output?.runningPID() {
            waitid(P_PGID, UInt32(shellPID), nil, 0)
        }
    }

    @MainActor
    func clearOutput() {
        output?.terminal.resetToInitialState()
        output?.feed(text: "")
    }

    private func createStatusTaskNotification() {
        let userInfo: [String: Any] = [
            "id": taskId,
            "action": "createWithPriority",
            "title": "Running \(self.task.name)",
            "message": "Running your task: \(self.task.name).",
            "isLoading": true,
            "workspace": workspaceURL as Any
        ]

        NotificationCenter.default.post(name: .taskNotification, object: nil, userInfo: userInfo)
    }

    private func deleteStatusTaskNotification() {
        let deleteInfo: [String: Any] = [
            "id": taskId,
            "action": "deleteWithDelay",
            "delay": 3.0,
            "workspace": workspaceURL as Any
        ]

        NotificationCenter.default.post(name: .taskNotification, object: nil, userInfo: deleteInfo)
    }

    private func updateTaskNotification(title: String? = nil, message: String? = nil, isLoading: Bool? = nil) {
        var userInfo: [String: Any] = [
            "id": taskId,
            "action": "update",
            "workspace": workspaceURL as Any
        ]
        if let title {
            userInfo["title"] = title
        }
        if let message {
            userInfo["message"] = message
        }
        if let isLoading {
            userInfo["isLoading"] = isLoading
        }

        NotificationCenter.default.post(name: .taskNotification, object: nil, userInfo: userInfo)
    }

    @MainActor
    func updateTaskStatus(to taskStatus: CETaskStatus) {
        self.status = taskStatus
    }

    static func == (lhs: CEActiveTask, rhs: CEActiveTask) -> Bool {
        return lhs.output == rhs.output &&
        lhs.status == rhs.status &&
        lhs.output?.process.shellPid == rhs.output?.process.shellPid &&
        lhs.task == rhs.task
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(output)
        hasher.combine(status)
        hasher.combine(task)
    }
}
