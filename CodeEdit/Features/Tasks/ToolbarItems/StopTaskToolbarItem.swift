//
//  StopTaskToolbarItem.swift
//  CodeEdit
//
//  Created by Khan Winter on 8/28/25.
//

import AppKit
import Combine
import Observation

@available(macOS 26, *)
final class StopTaskToolbarItem: NSToolbarItem {
    private weak var workspace: WorkspaceDocument?

    private var taskManager: TaskManager? {
        workspace?.taskManager
    }

    /// Whether a CMake build is running, tracked separately from task status because builds
    /// are not represented as active tasks.
    private var cmakeBuildRunning = false

    /// The listener that listens to the active task's status publisher. Is updated frequently as the active task
    /// changes.
    private var statusListener: AnyCancellable?
    private var otherListeners: Set<AnyCancellable> = []

    init?(workspace: WorkspaceDocument) {
        guard let taskManager = workspace.taskManager else { return nil }

        self.workspace = workspace
        super.init(itemIdentifier: NSToolbarItem.Identifier("StopTaskToolbarItem"))

        image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil)
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        image = image?.withSymbolConfiguration(config) ?? image

        paletteLabel = "Stop Task"
        toolTip = "Stop the selected task"
        target = self
        isEnabled = false
        isBordered = true

        taskManager.$selectedTaskID.sink { [weak self] selectedId in
            self?.updateStatusListener(activeTasks: taskManager.activeTasks, selectedId: selectedId)
        }
        .store(in: &otherListeners)

        taskManager.$activeTasks.sink { [weak self] activeTasks in
            self?.updateStatusListener(activeTasks: activeTasks, selectedId: taskManager.selectedTaskID)
        }
        .store(in: &otherListeners)

        if let buildController = workspace.cmakeBuildController {
            observeBuild(buildController)
        }

        updateStatusListener(activeTasks: taskManager.activeTasks, selectedId: taskManager.selectedTaskID)
    }

    /// Update the ``statusListener`` to listen to a potentially new active task.
    private func updateStatusListener(activeTasks: [UUID: CEActiveTask], selectedId: UUID?) {
        statusListener?.cancel()

        if let status = activeTasks[selectedId ?? UUID()]?.status {
            updateForNewStatus(status)
        }

        guard let id = selectedId else { return }
        statusListener = activeTasks[id]?.$status.sink { [weak self] status in
            self?.updateForNewStatus(status)
        }
    }

    private func updateForNewStatus(_ status: CETaskStatus) {
        isEnabled = status == .running || cmakeBuildRunning
        action = isEnabled ? #selector(stopTask) : nil
    }

    /// Tracks the build controller's `isBuilding` flag with observation tracking, since this
    /// item is AppKit and cannot rely on SwiftUI observation.
    private func observeBuild(_ controller: CMakeBuildController) {
        withObservationTracking {
            _ = controller.isBuilding
        } onChange: { [weak self, weak controller] in
            guard let self, let controller else { return }
            DispatchQueue.main.async {
                self.cmakeBuildRunning = controller.isBuilding
                if let status = self.taskManager?.activeTasks[self.taskManager?.selectedTaskID ?? UUID()]?.status {
                    self.updateForNewStatus(status)
                } else {
                    self.updateForNewStatus(.notRunning)
                }
                self.observeBuild(controller)
            }
        }
    }

    @objc
    func stopTask() {
        taskManager?.terminateActiveTask()
    }

    deinit {
        statusListener?.cancel()
        otherListeners.removeAll()
    }
}
