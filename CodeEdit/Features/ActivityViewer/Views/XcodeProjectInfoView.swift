//
//  XcodeProjectInfoView.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/17/26.
//

import SwiftUI

/// Inputs used to resolve the two-line activity status next to the project icon.
struct ActivityStatusInput {
    var notificationTitle: String?
    var runningTaskName: String?
    var finishedTaskName: String?
    var cmakeIsBuilding: Bool = false
    var cmakeStatusText: String = ""
    var cmakeOutcome: CMakeBuildController.Outcome = .none
}

/// Resolves the two-line activity status shown next to the project icon.
enum ActivityStatusResolver {
    static func status(_ input: ActivityStatusInput) -> String {
        if input.cmakeIsBuilding {
            return input.cmakeStatusText.isEmpty ? "Building..." : input.cmakeStatusText
        }
        if let runningTaskName = input.runningTaskName, !runningTaskName.isEmpty {
            return "Running \(runningTaskName)"
        }
        if let notificationTitle = input.notificationTitle, !notificationTitle.isEmpty {
            return notificationTitle
        }
        switch input.cmakeOutcome {
        case .success:
            return "Build Succeeded"
        case .failed:
            return "Build Failed"
        case .cancelled:
            return "Build Stopped"
        case .none:
            break
        }
        if let finishedTaskName = input.finishedTaskName, !finishedTaskName.isEmpty {
            return "Finished running \(finishedTaskName)"
        }
        return "Ready"
    }
}

/// Left-hand project information view showing the project icon, project name, and status text.
struct XcodeProjectInfoView: View {
    @ObservedObject var workspaceSettingsManager: CEWorkspaceSettings
    var workspaceFileManager: CEWorkspaceFileManager?
    @ObservedObject var taskNotificationHandler: TaskNotificationHandler
    @ObservedObject var taskManager: TaskManager
    var workspace: WorkspaceDocument?

    private var projectName: String {
        let name = workspaceSettingsManager.settings.project.projectName
        if !name.isEmpty {
            return name
        }
        return workspaceFileManager?.workspaceItem.fileName() ?? "CodeEdit"
    }

    var body: some View {
        HStack(spacing: 9) {
            projectIcon
            VStack(alignment: .leading, spacing: 0) {
                Text(projectName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                statusLabel
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // Toolbar items are measured by AppKit before the first SwiftUI
            // layout completes; sizing the text stack to its ideal width keeps
            // the status line from being truncated to the project name's width.
            .fixedSize()
        }
        .frame(minWidth: 140, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            openUtilityArea()
        }
        .help("Workspace: \(projectName)")
    }

    @ViewBuilder private var statusLabel: some View {
        if let cmake = workspace?.cmakeBuildController {
            CMakeAwareStatusText(
                cmake: cmake,
                notificationTitle: taskNotificationHandler.notifications.first?.title,
                runningTaskName: runningTaskName,
                finishedTaskName: finishedTaskName
            )
        } else {
            Text(
                ActivityStatusResolver.status(
                    ActivityStatusInput(
                        notificationTitle: taskNotificationHandler.notifications.first?.title,
                        runningTaskName: runningTaskName,
                        finishedTaskName: finishedTaskName
                    )
                )
            )
        }
    }

    private var runningTaskName: String? {
        taskManager.activeTasks.values.first { $0.status == .running }?.task.name
    }

    private var finishedTaskName: String? {
        if let selected = taskManager.selectedTask, !selected.name.isEmpty {
            return selected.name
        }
        return taskManager.activeTasks.values.first { $0.status == .finished }?.task.name
    }

    private var projectIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(
                    LinearGradient(
                        colors: [Color(nsColor: .systemBlue), Color.blue.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 30, height: 30)

            Image(systemName: "hammer.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private func openUtilityArea() {
        guard let utilityArea = workspace?.utilityAreaModel else {
            NSApp.sendAction(#selector(CodeEditWindowController.openWorkspaceSettings(_:)), to: nil, from: nil)
            return
        }
        let cmakeFailed: Bool
        if case .failed = workspace?.cmakeBuildController?.outcome {
            cmakeFailed = true
        } else {
            cmakeFailed = false
        }
        if cmakeFailed || taskManager.isCMakeBuildTarget {
            utilityArea.selectedTab = .problems
        } else {
            utilityArea.selectedTab = .debugConsole
        }
        if utilityArea.isCollapsed {
            utilityArea.isCollapsed = false
        }
    }
}

private struct CMakeAwareStatusText: View {
    var cmake: CMakeBuildController
    let notificationTitle: String?
    let runningTaskName: String?
    let finishedTaskName: String?

    var body: some View {
        Text(
            ActivityStatusResolver.status(
                ActivityStatusInput(
                    notificationTitle: notificationTitle,
                    runningTaskName: runningTaskName,
                    finishedTaskName: finishedTaskName,
                    cmakeIsBuilding: cmake.isBuilding,
                    cmakeStatusText: cmake.statusText,
                    cmakeOutcome: cmake.outcome
                )
            )
        )
    }
}
