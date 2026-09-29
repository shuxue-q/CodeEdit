//
//  StartTaskToolbarButton.swift
//  CodeEdit
//
//  Created by Austin Condiff on 8/4/24.
//

import SwiftUI

struct StartTaskToolbarButton: View {
    @Environment(\.controlActiveState)
    private var activeState

    @ObservedObject var taskManager: TaskManager
    @EnvironmentObject var workspace: WorkspaceDocument

    var utilityAreaCollapsed: Bool {
        workspace.utilityAreaModel?.isCollapsed ?? true
    }

    var body: some View {
        Button {
            taskManager.executeActiveTask()
            if utilityAreaCollapsed {
                CommandManager.shared.executeCommand("open.drawer")
            }
            workspace.utilityAreaModel?.selectedTab = taskManager.isCMakeBuildTarget ? .problems : .debugConsole
            taskManager.taskShowingOutput = taskManager.selectedTaskID
        } label: {
            Label("Run", systemImage: "play.fill")
                .labelStyle(.iconOnly)
                .font(.system(size: 17, weight: .regular))
                .toolbarCircleFeedback()
                .opacity(activeState == .inactive ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .help(taskManager.isCMakeBuildTarget ? "Build and then run the current target" : "Start selected task")
        .accessibilityLabel("Run")
    }
}
