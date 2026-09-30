//
//  ProjectEditorView.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/30/26.
//

import SwiftUI

/// The editor-area content of the workspace root's tab: project settings, like the project
/// editor Xcode shows when the project is selected in the navigator.
struct ProjectEditorView: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    /// Space taken by the toolbar, tab bar, and jump bar drawn over the editor area.
    @Environment(\.edgeInsets)
    private var edgeInsets

    /// The workspace root folder the tab represents.
    let file: CEWorkspaceFile

    var body: some View {
        if let store = workspace.cmakeProjectSettings, let cmakeWorkspace = workspace.cmakeWorkspace {
            CMakeProjectEditorView(store: store, cmakeWorkspace: cmakeWorkspace, folderName: file.name)
                .padding(.top, edgeInsets.top)
                .padding(.bottom, StatusBarView.height)
        } else {
            CEContentUnavailableView(
                "No Project Settings",
                description: "Project settings are available for CMake projects. "
                    + "Add a CMakeLists.txt to the workspace folder and reopen it.",
                systemImage: "gearshape.2"
            )
            .padding(.top, edgeInsets.top)
        }
    }
}

/// Toolchain, build, variable, and run settings of a CMake project.
private struct CMakeProjectEditorView: View {
    @Bindable var store: CMakeProjectSettingsStore
    let cmakeWorkspace: CMakeWorkspace
    let folderName: String

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                Picker("Section", selection: $store.selectedPane) {
                    ForEach(CMakeProjectSettingsStore.Pane.allCases) { pane in
                        Text(pane.rawValue).tag(pane)
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
                switch store.selectedPane {
                case .toolchain: CMakeToolchainPane(store: store)
                case .build: CMakeBuildSettingsPane(store: store, cmakeWorkspace: cmakeWorkspace)
                case .variables: CMakeVariablesPane(store: store)
                case .run: CMakeRunPane(store: store)
                }
            }
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ProjectEditor")
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

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "hammer.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(cmakeWorkspace.project?.name ?? folderName)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let error = store.loadError ?? store.saveError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .help("\(store.fileURL.path): \(error)")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var subtitle: String {
        var parts = ["CMake Project"]
        if let version = cmakeWorkspace.project?.version { parts.append("Version \(version)") }
        if let languages = cmakeWorkspace.project?.languages, !languages.isEmpty {
            parts.append(languages.joined(separator: ", "))
        }
        parts.append("Settings in .codeedit/\(CMakeProjectSettings.fileName)")
        return parts.joined(separator: " · ")
    }
}
