//
//  ActivityViewer.swift
//  CodeEdit
//
//  Created by Tommy Ludwig on 21.06.24.
//

import SwiftUI

/// The leading activity viewer group: history navigation followed by the project
/// name & status, pinned to the leading edge of the toolbar's activity area by a
/// following flexible space.
struct ActivityViewerLeading: View {
    var workspaceFileManager: CEWorkspaceFileManager?

    @ObservedObject var taskNotificationHandler: TaskNotificationHandler
    @ObservedObject var workspaceSettingsManager: CEWorkspaceSettings
    @ObservedObject var taskManager: TaskManager
    var workspace: WorkspaceDocument?

    var body: some View {
        HStack(spacing: 10) {
            XcodeHistoryCapsule()
            XcodeProjectInfoView(
                workspaceSettingsManager: workspaceSettingsManager,
                workspaceFileManager: workspaceFileManager,
                taskNotificationHandler: taskNotificationHandler,
                taskManager: taskManager,
                workspace: workspace
            )
        }
        .frame(height: 44)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activity Viewer Leading")
    }
}

/// The center activity viewer group: assistant and the scheme/destination picker
/// with issue badges. Centered in the toolbar by the surrounding flexible spaces.
struct ActivityViewer: View {
    var workspaceFileManager: CEWorkspaceFileManager?

    @ObservedObject var workspaceSettingsManager: CEWorkspaceSettings
    @ObservedObject var taskManager: TaskManager
    var workspace: WorkspaceDocument?

    var body: some View {
        HStack(spacing: 8) {
            XcodeAssistantButton()
            XcodeSchemeDestinationCapsule(
                workspaceSettingsManager: workspaceSettingsManager,
                workspaceFileManager: workspaceFileManager,
                taskManager: taskManager,
                workspace: workspace
            )
            XcodeWarningsCapsule(workspace: workspace)
            XcodeErrorsCapsule(workspace: workspace)
        }
        .frame(height: 44)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activity Viewer")
    }
}

/// The trailing activity viewer group: split/options, layout modes, and the inspector
/// toggle, pinned to the trailing edge of the toolbar by a preceding flexible space.
struct ActivityViewerTrailing: View {
    var workspace: WorkspaceDocument?

    var body: some View {
        HStack(spacing: 6) {
            XcodeSplitOptionsCapsule(workspace: workspace)
            XcodeLayoutModesCapsule(workspace: workspace)
            XcodeInspectorToggleCapsule()
        }
        .frame(height: 44)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activity Viewer Controls")
    }
}
