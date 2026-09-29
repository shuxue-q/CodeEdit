//
//  XcodeSchemeDestinationCapsule.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/17/26.
//

import SwiftUI

/// Center Scheme and Destination capsule replicating Xcode's `[ (Target) Scheme > (Mac) Destination ]` control.
struct XcodeSchemeDestinationCapsule: View {
    @ObservedObject var workspaceSettingsManager: CEWorkspaceSettings
    var workspaceFileManager: CEWorkspaceFileManager?
    @ObservedObject var taskManager: TaskManager
    var workspace: WorkspaceDocument?

    @State private var isPopoverPresented: Bool = false
    @State private var isHovered: Bool = false

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

    var body: some View {
        XcodeCapsuleContainer(horizontalPadding: 10) {
            HStack(spacing: 7) {
                targetIcon

                Text(schemeName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 0.75, height: 16)

                destinationIcon

                Text("My Mac")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .contentShape(Capsule())
        }
        .onHover { isHovered = $0 }
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
        Image(systemName: "laptopcomputer")
            .font(.system(size: 17))
            .symbolRenderingMode(.palette)
            .foregroundStyle(Color(nsColor: .systemBlue), Color.secondary)
    }

    @ViewBuilder private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            destinationSection
            Divider()
                .padding(.vertical, 3)
            tasksSection
            cmakeSection
            Divider()
                .padding(.vertical, 3)
            optionsSection
        }
        .padding(8)
        .frame(minWidth: 200)
    }

    @ViewBuilder private var destinationSection: some View {
        HStack {
            Image(systemName: "laptopcomputer")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color(nsColor: .systemBlue), Color.secondary)
            Text("My Mac")
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.accentColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
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

    @ViewBuilder private var cmakeSection: some View {
        if let cmake = workspace?.cmakeWorkspace, let project = cmake.project, !project.configurePresets.isEmpty {
            Text("CMake Presets")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.top, 2)
            ForEach(project.configurePresets, id: \.id) { preset in
                OptionMenuItemView(label: preset.title) {
                    cmake.selectConfigurePreset(preset.name)
                    isPopoverPresented = false
                }
            }
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
