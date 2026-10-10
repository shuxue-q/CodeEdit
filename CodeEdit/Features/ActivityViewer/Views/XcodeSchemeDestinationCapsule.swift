//
//  XcodeSchemeDestinationCapsule.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/17/26.
//

import SwiftUI

/// Center Scheme and Destination capsule replicating Xcode's `[ (Target) Scheme > (Mac) Destination ]` control.
/// In a CMake workspace the destination segment shows the selected configure preset; other
/// workspaces show the scheme segment only.
struct XcodeSchemeDestinationCapsule: View {
    @ObservedObject var workspaceSettingsManager: CEWorkspaceSettings
    var workspaceFileManager: CEWorkspaceFileManager?
    @ObservedObject var taskManager: TaskManager
    var workspace: WorkspaceDocument?

    @State private var isPopoverPresented: Bool = false

    private var projectName: String {
        let name = workspaceSettingsManager.settings.project.projectName
        if !name.isEmpty {
            return name
        }
        return workspaceFileManager?.workspaceItem.fileName() ?? "CodeEdit"
    }

    private var schemeName: String {
        if let task = taskManager.selectedTask, !task.name.isEmpty {
            return task.name
        }
        if let cmakeName = workspace?.cmakeWorkspace?.project?.name, !cmakeName.isEmpty {
            return cmakeName
        }
        return projectName
    }

    /// The workspace's CMake model, present only for folders with a root `CMakeLists.txt`.
    private var cmake: CMakeWorkspace? {
        workspace?.cmakeWorkspace
    }

    /// Text of the destination segment for a CMake configure preset selection.
    static func destinationTitle(presetTitle: String?) -> String {
        guard let presetTitle, !presetTitle.isEmpty else { return "No Preset" }
        return presetTitle
    }

    var body: some View {
        XcodeCapsuleContainer(horizontalPadding: ToolbarMetrics.textCapsulePadding) {
            HStack(spacing: 7) {
                targetIcon

                Text(schemeName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                if let cmake {
                    ToolbarSeparator()

                    destinationIcon

                    Text(Self.destinationTitle(presetTitle: cmake.configurePreset?.title))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .contentShape(Capsule())
        }
        .onTapGesture {
            isPopoverPresented.toggle()
        }
        .instantPopover(isPresented: $isPopoverPresented, arrowEdge: .top) {
            popoverContent
        }
        .help("Select Scheme and Run Destination")
    }

    private var schemeInitial: String {
        String(schemeName.prefix(1)).uppercased()
    }

    private var targetIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5.5)
                .fill(Color.secondary.opacity(0.85))
                .frame(width: 22, height: 22)

            Text(schemeInitial)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }

    private var destinationIcon: some View {
        Image(systemName: "gearshape")
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let cmake, let project = cmake.project, !project.configurePresets.isEmpty {
                destinationSection(cmake: cmake, project: project)
                Divider()
                    .padding(.vertical, 3)
            }
            tasksSection
            Divider()
                .padding(.vertical, 3)
            optionsSection
        }
        .padding(8)
        .frame(minWidth: 200)
    }

    /// The configure presets of a CMake workspace; picking one makes it the selected preset.
    @ViewBuilder
    private func destinationSection(cmake: CMakeWorkspace, project: CMakeProject) -> some View {
        Text("Configure Preset")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
        ForEach(project.configurePresets, id: \.id) { preset in
            Button {
                cmake.selectConfigurePreset(preset.name)
                isPopoverPresented = false
            } label: {
                HStack {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                    Text(preset.title)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    if preset.name == cmake.selectedConfigurePreset {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var tasksSection: some View {
        if !taskManager.availableTasks.isEmpty {
            ForEach(taskManager.availableTasks, id: \.id) { task in
                TasksPopoverMenuItem(taskManager: taskManager, task: task) {
                    isPopoverPresented = false
                }
            }
        } else if workspace?.cmakeWorkspace == nil {
            Text("No Tasks Configured")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
        }
    }

    @ViewBuilder private var optionsSection: some View {
        OptionMenuItemView(label: "Add Task...") {
            isPopoverPresented = false
            NSApp.sendAction(#selector(CodeEditWindowController.openWorkspaceSettings(_:)), to: nil, from: nil)
        }
        OptionMenuItemView(label: "Manage Tasks...") {
            isPopoverPresented = false
            NSApp.sendAction(#selector(CodeEditWindowController.openWorkspaceSettings(_:)), to: nil, from: nil)
        }
        OptionMenuItemView(label: "Workspace Settings...") {
            isPopoverPresented = false
            NSApp.sendAction(#selector(CodeEditWindowController.openWorkspaceSettings(_:)), to: nil, from: nil)
        }
    }
}
