//
//  TaskManager+GeneratedTasks.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

extension TaskManager {
    /// Replaces the generated tasks. The selection is kept when its task still exists.
    /// - Parameter tasks: Tasks from ``ProjectTaskCatalog``.
    func setGeneratedTasks(_ tasks: [GeneratedTask]) {
        let newIDs = tasks.map(\.id)
        guard newIDs != generatedTasks.map(\.id)
                || tasks.map(\.command) != generatedTasks.map(\.command)
                || tasks.map(\.info) != newIDs.compactMap({ generatedTaskInfo[$0] }) else {
            return
        }
        // Keep the task objects of tasks that still exist: an active task holds on to its task.
        let existing = Dictionary(generatedTasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        generatedTasks = tasks.map { generated in
            guard let task = existing[generated.id] else { return generated.makeTask() }
            generated.update(task)
            return task
        }
        generatedTaskInfo = Dictionary(tasks.map { ($0.id, $0.info) }, uniquingKeysWith: { first, _ in first })
        if let selectedTaskID, !availableTasks.contains(where: { $0.id == selectedTaskID }) {
            self.selectedTaskID = availableTasks.first?.id
        } else if selectedTaskID == nil {
            selectedTaskID = availableTasks.first?.id
        }
    }

    /// What a generated task is, or `nil` for a user task.
    func generatedInfo(for taskID: UUID?) -> GeneratedTaskInfo? {
        taskID.flatMap { generatedTaskInfo[$0] }
    }

    /// The generated info of the selected task.
    var selectedGeneratedInfo: GeneratedTaskInfo? {
        generatedInfo(for: selectedTaskID ?? availableTasks.first?.id)
    }

    /// Selects and runs the generated task with `role` for `toolchain`, for buttons such as
    /// "Run pub get" in the project editor.
    func runGeneratedTask(toolchain: ProjectToolchain, role: GeneratedTaskInfo.Role, named name: String? = nil) {
        guard let task = generatedTasks.first(where: { task in
            guard let info = generatedTaskInfo[task.id] else { return false }
            return info.toolchain == toolchain && info.role == role && (name == nil || task.name == name)
        }) else { return }
        selectedTaskID = task.id
        Task { await runTask(task: task) }
    }

    // MARK: - Output monitoring

    /// How long a finished run's monitor keeps reading: the terminal can deliver a process's last
    /// output after it reports the exit.
    static let trailingOutputDelay: Duration = .milliseconds(300)

    /// Waits until the previous run's trailing output had time to arrive, so it is read by that
    /// run's monitor and not by the next run's.
    func waitForTrailingOutput(of activeTask: CEActiveTask) async {
        guard let finished = activeTask.lastFinishDate else { return }
        let remaining = Self.trailingOutputDelay - .seconds(Date().timeIntervalSince(finished))
        if remaining > .zero {
            try? await Task.sleep(for: remaining)
        }
    }

    /// Attaches a fresh output monitor to a generated task's run, or detaches it for a user task.
    func prepareOutputMonitor(for activeTask: CEActiveTask, task: CETask) {
        let taskID = task.id
        hotReloadReadyTaskIDs.remove(taskID)
        // Finish the previous run's monitor now, so its last lines are not read as this run's.
        outputMonitors[taskID]?.finish()
        guard let info = generatedTaskInfo[taskID], let workspaceURL else {
            activeTask.outputObserver = nil
            activeTask.onProcessFinished = nil
            outputMonitors[taskID] = nil
            return
        }
        let baseDirectory = task.workingDirectory.isEmpty
            ? workspaceURL.standardizedFileURL
            : workspaceURL.appending(path: task.workingDirectory, directoryHint: .isDirectory).standardizedFileURL
        let monitor = TaskOutputMonitor(
            taskID: taskID,
            name: task.name,
            parserKind: info.outputParser,
            baseDirectory: baseDirectory,
            store: diagnosticsStore,
            watchesFlutterRun: info.supportsHotReload
        )
        monitor.onFlutterRunEvent = { [weak self] event in
            self?.handleFlutterRunEvent(event, taskID: taskID)
        }
        outputMonitors[taskID] = monitor
        activeTask.outputObserver = { [weak monitor] bytes in
            monitor?.consume(bytes)
        }
        activeTask.onProcessFinished = { [weak self, weak monitor] in
            self?.hotReloadReadyTaskIDs.remove(taskID)
            Task { @MainActor [weak monitor] in
                try? await Task.sleep(for: Self.trailingOutputDelay)
                monitor?.finish()
            }
        }
    }

    // MARK: - Hot reload

    /// The running `flutter run` task hot reload targets: the selected one when it is ready,
    /// else any ready one.
    var hotReloadTaskID: UUID? {
        if let selectedTaskID, hotReloadReadyTaskIDs.contains(selectedTaskID) { return selectedTaskID }
        return hotReloadReadyTaskIDs.sorted { $0.uuidString < $1.uuidString }.first
    }

    /// Whether a running app accepts hot reload.
    var canHotReload: Bool { hotReloadTaskID != nil }

    /// Hot reloads (`r`) or hot restarts (`R`) the running Flutter app.
    /// - Returns: Whether a key was sent.
    @discardableResult
    func hotReload(restart: Bool = false) -> Bool {
        guard let taskID = hotReloadTaskID, let activeTask = activeTasks[taskID],
              activeTask.sendInput(restart ? "R" : "r") else { return false }
        postHotReloadNotification(
            taskID: taskID,
            title: restart
                ? String(localized: "Hot Restarting…")
                : String(localized: "Hot Reloading…"),
            isLoading: true,
            removeAfter: nil
        )
        return true
    }

    /// Stops a running `flutter run` by typing `q`, so the app quits and Flutter cleans up, then
    /// terminates the task if it is still running a few seconds later.
    /// - Returns: Whether the task was a running Flutter run task.
    func stopFlutterRunGracefully(taskID: UUID) -> Bool {
        guard generatedTaskInfo[taskID]?.supportsHotReload == true,
              hotReloadReadyTaskIDs.contains(taskID),
              let activeTask = activeTasks[taskID],
              activeTask.sendInput("q") else { return false }
        Task { [weak activeTask] in
            try? await Task.sleep(for: .seconds(4))
            guard let activeTask, activeTask.status == .running else { return }
            activeTask.terminate()
        }
        return true
    }

    private func handleFlutterRunEvent(_ event: TaskOutputMonitor.FlutterRunEvent, taskID: UUID) {
        switch event {
        case .readyForHotReload:
            hotReloadReadyTaskIDs.insert(taskID)
        case .reloaded(let summary):
            postHotReloadNotification(taskID: taskID, title: summary, isLoading: false, removeAfter: 2)
        case .reloadFailed(let message):
            postHotReloadNotification(taskID: taskID, title: message, isLoading: false, removeAfter: 4)
        }
    }

    private func postHotReloadNotification(taskID: UUID, title: String, isLoading: Bool, removeAfter delay: Double?) {
        let id = "hot-reload-\(taskID.uuidString)"
        var userInfo: [String: Any] = [
            "id": id,
            "action": "createWithPriority",
            "title": title,
            "isLoading": isLoading,
            "workspace": workspaceURL as Any
        ]
        // Replace a previous hot reload notification of the task.
        NotificationCenter.default.post(name: .taskNotification, object: nil, userInfo: [
            "id": id, "action": "delete", "workspace": workspaceURL as Any
        ])
        NotificationCenter.default.post(name: .taskNotification, object: nil, userInfo: userInfo)
        if let delay {
            userInfo = ["id": id, "action": "deleteWithDelay", "delay": delay, "workspace": workspaceURL as Any]
            NotificationCenter.default.post(name: .taskNotification, object: nil, userInfo: userInfo)
        }
    }
}
