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
/// toolchain, build, variable, and run settings.
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
    let folderName: String
    let openInTab: (ProjectTextFile) -> Void

    private var sections: [ProjectEditorState.Section] {
        let cmakeSections = cmakeStore == nil || cmakeWorkspace == nil
            ? []
            : CMakeProjectSettingsStore.Pane.allCases.map { ProjectEditorState.Section.cmake($0) }
        return cmakeSections + [.versionControl, .projectFiles]
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

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: cmakeWorkspace == nil ? "folder.circle.fill" : "hammer.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(cmakeWorkspace?.project?.name ?? folderName)
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

    private var subtitle: String {
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
