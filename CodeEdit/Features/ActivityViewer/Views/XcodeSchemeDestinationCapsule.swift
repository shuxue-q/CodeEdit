//
//  XcodeSchemeDestinationCapsule.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/17/26.
//

import SwiftUI

/// Center Scheme and Destination capsule replicating Xcode's `[ (Target) Scheme > (Mac) Destination ]` control.
/// The destination segment follows the selected task: a Flutter task shows its device and build
/// mode, a Cargo task its profile, and a CMake workspace the selected configure preset; other
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

                if let destination {
                    ToolbarSeparator()

                    Image(systemName: destination.symbol)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)

                    Text(destination.title)
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
        .accessibilityIdentifier("SchemeDestinationCapsule")
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

    /// What the destination segment shows for the selected task.
    private var destination: (symbol: String, title: String)? {
        let info = taskManager.selectedGeneratedInfo
        switch info?.toolchain {
        case .flutter?:
            if let flutter = workspace?.flutterWorkspace {
                return (Self.deviceSymbol(flutter.selectedDevice), Self.flutterDestinationTitle(
                    device: flutter.selectedDevice.name,
                    mode: flutter.settings.value.buildMode
                ))
            }
        case .cargo?:
            if let settings = workspace?.projectInventory?.cargoSettings, let info {
                return ("shippingbox", settings.value.root(info.componentPath).profile)
            }
        case .cmake?, nil:
            break
        }
        if let cmake {
            return ("gearshape", Self.destinationTitle(presetTitle: cmake.configurePreset?.title))
        }
        return nil
    }

    /// Text of the destination segment for a Flutter task, such as `macOS · Debug`.
    static func flutterDestinationTitle(device: String, mode: FlutterBuildMode) -> String {
        "\(device) · \(mode.title)"
    }

    private static func deviceSymbol(_ device: FlutterDevice) -> String {
        switch device.buildPlatform {
        case .ios?: "iphone"
        case .android?: "smartphone"
        case .web?: "globe"
        default: "desktopcomputer"
        }
    }

    @ViewBuilder private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let flutter = workspace?.flutterWorkspace, hasGeneratedTasks(for: .flutter) {
                flutterSection(flutter)
                Divider()
                    .padding(.vertical, 3)
            }
            if let inventory = workspace?.projectInventory, let root = inventory.inventory?.cargoRoots.first,
               hasGeneratedTasks(for: .cargo) {
                cargoSection(model: inventory, root: root)
                Divider()
                    .padding(.vertical, 3)
            }
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
        .task {
            // Device listing takes a few seconds; start it the first time the menu opens.
            if let flutter = workspace?.flutterWorkspace, hasGeneratedTasks(for: .flutter),
               !flutter.hasListedDevices, !flutter.isListingDevices {
                flutter.refreshDevices()
            }
        }
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
            ForEach(taskManager.workspaceSettings.tasks, id: \.id) { task in
                TasksPopoverMenuItem(taskManager: taskManager, task: task) {
                    isPopoverPresented = false
                }
            }
            ForEach(generatedGroups, id: \.self) { group in
                sectionTitle(group)
                    .padding(.top, 2)
                let tasks = taskManager.generatedTasks.filter { taskManager.generatedTaskInfo[$0.id]?.group == group }
                ForEach(tasks) { task in
                    TasksPopoverMenuItem(taskManager: taskManager, task: task) {
                        isPopoverPresented = false
                    }
                }
            }
        } else if workspace?.cmakeWorkspace == nil {
            Text("No Tasks Configured")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
        }
    }

    /// Generated task groups in list order.
    private var generatedGroups: [String] {
        var groups: [String] = []
        for task in taskManager.generatedTasks {
            if let group = taskManager.generatedTaskInfo[task.id]?.group, !groups.contains(group) {
                groups.append(group)
            }
        }
        return groups
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

// MARK: - Flutter and Cargo choices

extension XcodeSchemeDestinationCapsule {
    private func hasGeneratedTasks(for toolchain: ProjectToolchain) -> Bool {
        taskManager.generatedTaskInfo.values.contains { $0.toolchain == toolchain }
    }

    /// A small caption above a group of rows.
    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
    }

    /// A row that shows a checkmark when it is the current choice.
    private func choiceRow(
        _ title: String,
        symbol: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            isPopoverPresented = false
        } label: {
            HStack {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if isSelected {
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

    /// The Flutter device and build mode the Run and Build tasks use.
    @ViewBuilder
    private func flutterSection(_ flutter: FlutterWorkspace) -> some View {
        sectionTitle("Flutter Device")
        let selected = flutter.selectedDevice
        let devices = flutter.devices.isEmpty ? [FlutterDevice.macOS] : flutter.devices
        ForEach(devices.contains(selected) ? devices : devices + [selected]) { device in
            choiceRow(device.name, symbol: Self.deviceSymbol(device), isSelected: device.id == selected.id) {
                flutter.settings.value.device = device.id == FlutterDevice.macOS.id ? nil : device.id
            }
        }
        sectionTitle("Build Mode")
        ForEach(FlutterBuildMode.allCases) { mode in
            choiceRow(mode.title, symbol: "slider.horizontal.3", isSelected: flutter.settings.value.buildMode == mode) {
                flutter.settings.value.buildMode = mode
            }
        }
    }

    /// The Cargo profile of the first Cargo root.
    @ViewBuilder
    private func cargoSection(model: ProjectInventoryModel, root: CargoRoot) -> some View {
        let path = model.inventory?.relativePath(of: root.directory) ?? "."
        sectionTitle("Cargo Profile")
        ForEach(root.profiles.filter { $0.name != "test" && $0.name != "bench" }) { profile in
            choiceRow(
                profile.name,
                symbol: "shippingbox",
                isSelected: model.cargoSettings.value.root(path).profile == profile.name
            ) {
                model.cargoSettings.value.roots[path, default: CargoProjectSettings.Root()].profile = profile.name
            }
        }
    }
}
