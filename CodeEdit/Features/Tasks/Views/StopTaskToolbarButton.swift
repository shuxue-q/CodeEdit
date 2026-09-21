//
//  StopTaskToolbarButton.swift
//  CodeEdit
//
//  Created by Austin Condiff on 8/3/24.
//

import SwiftUI
import Combine

struct StopTaskToolbarButton: View {
    @Environment(\.controlActiveState)
    private var activeState

    @ObservedObject var taskManager: TaskManager

    /// Tracks the current selected task's status. Updated by `updateStatusListener`
    @State private var currentSelectedStatus: CETaskStatus?
    /// The listener that listens to the active task's status publisher. Is updated frequently as the active task
    /// changes.
    @State private var statusListener: AnyCancellable?

    var body: some View {
        StopTaskButtonContent(
            taskManager: taskManager,
            currentSelectedStatus: currentSelectedStatus,
            cmake: taskManager.cmakeBuildController,
            activeState: activeState
        )
        .onChange(of: taskManager.selectedTaskID) { _, _ in updateStatusListener() }
        .onChange(of: taskManager.activeTasks) { _, _ in updateStatusListener() }
        .onAppear(perform: updateStatusListener)
        .onDisappear {
            statusListener?.cancel()
        }
    }

    /// Whether stop can terminate the selected task or an in-flight CMake build.
    static func isStopEnabled(selectedStatus: CETaskStatus?, cmakeIsBuilding: Bool) -> Bool {
        selectedStatus == .running || cmakeIsBuilding
    }

    /// Update the ``statusListener`` to listen to a potentially new active task.
    private func updateStatusListener() {
        statusListener?.cancel()
        currentSelectedStatus = taskManager.activeTasks[taskManager.selectedTaskID ?? UUID()]?.status
        guard let id = taskManager.selectedTaskID else { return }
        statusListener = taskManager.activeTasks[id]?.$status.sink { newValue in
            currentSelectedStatus = newValue
        }
    }
}

/// Renders the stop control and observes CMake ``isBuilding`` through the `@Observable` controller.
private struct StopTaskButtonContent: View {
    @ObservedObject var taskManager: TaskManager
    var currentSelectedStatus: CETaskStatus?
    var cmake: CMakeBuildController?
    var activeState: ControlActiveState

    private var isEnabled: Bool {
        StopTaskToolbarButton.isStopEnabled(
            selectedStatus: currentSelectedStatus,
            cmakeIsBuilding: cmake?.isBuilding == true
        )
    }

    var body: some View {
        Button {
            taskManager.terminateActiveTask()
        } label: {
            Label("Stop", systemImage: "stop.fill")
                .labelStyle(.iconOnly)
                .font(.system(size: 17, weight: .regular))
                .toolbarPillFeedback()
                .opacity(activeState == .inactive ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.35)
        .help(taskManager.isCMakeBuildTarget ? "Stop the running build" : "Stop the running task")
        .accessibilityLabel("Stop")
    }
}
