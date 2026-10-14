//
//  ProjectEditorView.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/30/26.
//

import SwiftUI

/// The editor-area content of the workspace root's tab: project settings, like the project
/// editor Xcode shows when the project is selected in the navigator.
///
/// Every workspace gets the Version Control and Project Files sections; CMake projects also get
/// toolchain, build, variable, and run settings, Flutter projects a Flutter section and Cargo
/// projects a Rust section. A workspace combining several toolchains gets an Overview, and its
/// CMake panes are grouped under one C++ section.
struct ProjectEditorView: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    /// Space taken by the toolbar, tab bar, and jump bar drawn over the editor area.
    @Environment(\.edgeInsets)
    private var edgeInsets

    /// The workspace root folder the tab represents.
    let file: CEWorkspaceFile

    var body: some View {
        if let state = workspace.projectEditorState {
            ProjectEditorContent(
                state: state,
                cmakeStore: workspace.cmakeProjectSettings,
                cmakeWorkspace: workspace.cmakeWorkspace,
                flutterWorkspace: workspace.flutterWorkspace,
                inventoryModel: workspace.projectInventory,
                folderName: file.name,
                openInTab: openInTab
            )
            .padding(.top, edgeInsets.top)
            .padding(.bottom, StatusBarView.height)
        } else {
            CEContentUnavailableView(
                "No Project Settings",
                description: "Project settings are unavailable for this workspace.",
                systemImage: "gearshape.2"
            )
            .padding(.top, edgeInsets.top)
        }
    }

    /// Opens a configuration file in its own editor tab, even when the navigator hides it.
    private func openInTab(_ textFile: ProjectTextFile) {
        guard let item = workspace.workspaceFileManager?.getFile(textFile.url.path, createIfNotFound: true) else {
            return
        }
        workspace.editorManager?.openTab(item: item)
    }
}

/// The header, section picker, and selected section of the project editor.
private struct ProjectEditorContent: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    @Bindable var state: ProjectEditorState
    let cmakeStore: CMakeProjectSettingsStore?
    let cmakeWorkspace: CMakeWorkspace?
    let flutterWorkspace: FlutterWorkspace?
    let inventoryModel: ProjectInventoryModel?
    let folderName: String
    let openInTab: (ProjectTextFile) -> Void

    /// The Flutter model, once discovery recognized a Flutter project.
    private var flutterProject: FlutterProject? { flutterWorkspace?.project }

    private var inventory: ProjectInventory? { inventoryModel?.inventory }

    private var hasCargo: Bool { inventory?.cargoRoots.isEmpty == false }

    private var sections: [ProjectEditorState.Section] {
        var sections: [ProjectEditorState.Section] = []
        if inventory?.isHybrid == true { sections.append(.overview) }
        if flutterProject != nil { sections.append(.flutter) }
        if hasCargo { sections.append(.rust) }
        if cmakeStore != nil && cmakeWorkspace != nil {
            // Next to other toolchains the four CMake panes share one segment.
            if sections.isEmpty {
                sections += CMakeProjectSettingsStore.Pane.allCases.map { ProjectEditorState.Section.cmake($0) }
            } else {
                sections.append(.cpp)
            }
        }
        return sections + [.versionControl, .projectFiles]
    }

    private var selectedSection: ProjectEditorState.Section {
        if let selected = state.selectedSection, sections.contains(selected) { return selected }
        return sections[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                Picker("Section", selection: Binding(
                    get: { selectedSection },
                    set: { state.selectedSection = $0 }
                )) {
                    ForEach(sections) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.bottom, 10)
                .accessibilityIdentifier("ProjectEditorPanePicker")

                Divider()
            }
            .background(Color(nsColor: .windowBackgroundColor))
            // A grouped form's scroll view reaches into the top safe area; keep the header above
            // it so the header stays visible and its picker receives clicks.
            .zIndex(1)

            Group {
                switch selectedSection {
                case .overview:
                    if let inventoryModel {
                        ProjectOverviewPane(
                            model: inventoryModel,
                            flutterWorkspace: flutterWorkspace,
                            select: { state.selectedSection = $0 }
                        )
                    }
                case .flutter:
                    if let flutterWorkspace {
                        FlutterProjectPane(
                            flutterWorkspace: flutterWorkspace,
                            inventory: inventory,
                            runTask: runGeneratedTask
                        )
                    }
                case .rust:
                    if let inventoryModel {
                        RustProjectPane(model: inventoryModel, state: state, runTask: runGeneratedTask)
                    }
                case .cpp:
                    if let cmakeStore, let cmakeWorkspace {
                        CPPSectionView(state: state, store: cmakeStore, cmakeWorkspace: cmakeWorkspace)
                    }
                case .cmake(let pane):
                    if let cmakeStore, let cmakeWorkspace {
                        CMakeSectionView(pane: pane, store: cmakeStore, cmakeWorkspace: cmakeWorkspace)
                    }
                case .versionControl:
                    if let sourceControlManager = workspace.sourceControlManager {
                        VersionControlPane(
                            sourceControlManager: sourceControlManager,
                            gitignore: state.gitignore,
                            openInTab: openInTab
                        )
                    }
                case .projectFiles:
                    ProjectFilesPane(
                        state: state,
                        workspaceSettings: workspace.workspaceSettingsManager,
                        openInTab: openInTab
                    )
                }
            }
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ProjectEditor")
        .task {
            // Content changes are not forwarded by the workspace file manager's observers, so poll
            // while the editor is visible to pick up edits made elsewhere.
            while !Task.isCancelled {
                state.checkForExternalChanges()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Runs a generated task and shows its output.
    private func runGeneratedTask(_ toolchain: ProjectToolchain, _ role: GeneratedTaskInfo.Role) {
        workspace.taskManager?.runGeneratedTask(toolchain: toolchain, role: role)
        if workspace.utilityAreaModel?.isCollapsed == true {
            CommandManager.shared.executeCommand("open.drawer")
        }
        workspace.utilityAreaModel?.selectedTab = .debugConsole
        workspace.taskManager?.taskShowingOutput = workspace.taskManager?.selectedTaskID
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: headerSymbol)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(flutterProject?.name ?? cmakeWorkspace?.project?.name ?? folderName)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let cmakeStore, let error = cmakeStore.loadError ?? cmakeStore.saveError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .help("\(cmakeStore.fileURL.path): \(error)")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var headerSymbol: String {
        if inventory?.isHybrid == true { return "square.stack.3d.up.fill" }
        if flutterProject != nil { return "macwindow.on.rectangle" }
        if hasCargo && cmakeWorkspace == nil { return "shippingbox.circle.fill" }
        return cmakeWorkspace == nil ? "folder.circle.fill" : "hammer.circle.fill"
    }

    private var subtitle: String {
        if let inventory, inventory.isHybrid {
            var parts = [inventory.toolchains.map(\.title).joined(separator: " + ")]
            if let version = flutterProject?.pubspec.version { parts.append("Version \(version)") }
            parts.append("\(inventory.components.count) components")
            return parts.joined(separator: " · ")
        }
        if let flutterProject {
            var parts = [flutterProject.isFFIPlugin ? "Flutter FFI Plugin" : "Flutter Project"]
            if let version = flutterProject.pubspec.version { parts.append("Version \(version)") }
            if let flutterWorkspace, let root = flutterWorkspace.activeNativeRoot {
                parts.append("Native code: \(flutterWorkspace.displayName(of: root))")
            }
            return parts.joined(separator: " · ")
        }
        if cmakeWorkspace == nil, let root = inventory?.cargoRoots.first {
            return root.isWorkspace ? "Cargo Workspace · \(root.packages.count) packages" : "Cargo Package"
        }
        guard let cmakeWorkspace else { return "Folder · \(state.rootURL.path)" }
        var parts = ["CMake Project"]
        if let version = cmakeWorkspace.project?.version { parts.append("Version \(version)") }
        if let languages = cmakeWorkspace.project?.languages, !languages.isEmpty {
            parts.append(languages.joined(separator: ", "))
        }
        parts.append("Settings in .codeedit/\(CMakeProjectSettings.fileName)")
        return parts.joined(separator: " · ")
    }
}

/// One CMake section of the project editor, loading the project and toolchain on first show.
private struct CMakeSectionView: View {
    let pane: CMakeProjectSettingsStore.Pane
    @Bindable var store: CMakeProjectSettingsStore
    let cmakeWorkspace: CMakeWorkspace

    var body: some View {
        Group {
            switch pane {
            case .toolchain: CMakeToolchainPane(store: store)
            case .build: CMakeBuildSettingsPane(store: store, cmakeWorkspace: cmakeWorkspace)
            case .variables: CMakeVariablesPane(store: store)
            case .run: CMakeRunPane(store: store)
            }
        }
        .task {
            if cmakeWorkspace.project == nil && !cmakeWorkspace.isLoading {
                cmakeWorkspace.reload()
            }
            store.scanToolchain()
            store.refreshExecutableTargets()
        }
        .onChange(of: store.configureOptions.buildDirectory) {
            store.refreshExecutableTargets()
        }
    }
}

/// The C++ section of a workspace with several toolchains: the CMake panes behind their own picker.
private struct CPPSectionView: View {
    @Bindable var state: ProjectEditorState
    @Bindable var store: CMakeProjectSettingsStore
    let cmakeWorkspace: CMakeWorkspace

    var body: some View {
        VStack(spacing: 0) {
            Picker("C++ Settings", selection: $state.selectedCMakePane) {
                ForEach(CMakeProjectSettingsStore.Pane.allCases) { pane in
                    Text(pane.rawValue).tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, 10)
            .accessibilityIdentifier("ProjectEditorCMakePanePicker")
            CMakeSectionView(pane: state.selectedCMakePane, store: store, cmakeWorkspace: cmakeWorkspace)
        }
    }
}
