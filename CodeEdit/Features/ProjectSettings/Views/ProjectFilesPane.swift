//
//  ProjectFilesPane.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/30/26.
//

import SwiftUI

/// The project editor's Project Files section: editors for hidden configuration files and the
/// navigator's exclusion patterns.
struct ProjectFilesPane: View {
    @Bindable var state: ProjectEditorState
    let workspaceSettings: CEWorkspaceSettings?
    let openInTab: (ProjectTextFile) -> Void

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    fileList
                    if let file = state.configurationFiles.first(where: { $0.id == state.selectedConfigurationFile }) {
                        ProjectTextFileEditor(file: file) { openInTab(file) }
                            .id(file.id)
                    }
                }
                .frame(minHeight: 300)
            } header: {
                Text("Configuration Files")
            } footer: {
                Text("Hidden files are not shown in the project navigator unless Show Hidden Files is on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let workspaceSettings {
                NavigatorExclusionsSection(workspaceSettings: workspaceSettings, settings: workspaceSettings.settings)
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("ProjectEditorProjectFiles")
    }

    private var fileList: some View {
        List(state.configurationFiles, selection: $state.selectedConfigurationFile) { file in
            HStack(spacing: 6) {
                Image(systemName: file.exists ? "doc.text" : "doc.badge.plus")
                    .foregroundStyle(file.exists ? .primary : .secondary)
                Text(file.displayPath)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(file.exists ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if file.hasUnsavedChanges {
                    Circle().fill(.secondary).frame(width: 6, height: 6)
                        .help("Unsaved changes")
                }
            }
            .help(file.exists ? file.displayPath : "\(file.displayPath) (not created)")
            .tag(file.id)
        }
        .listStyle(.bordered)
        .frame(width: 230)
        .accessibilityIdentifier("ProjectConfigurationFileList")
    }
}

/// Edits ``NavigatorSettings/excludedPatterns`` and saves each change.
private struct NavigatorExclusionsSection: View {
    let workspaceSettings: CEWorkspaceSettings
    @ObservedObject var settings: CEWorkspaceSettingsData

    @State private var patterns: [GlobPattern] = []
    @State private var selection: Set<UUID> = []

    var body: some View {
        Section {
            Toggle("Show Hidden Files", isOn: Binding(
                get: { settings.navigator.showHiddenFiles },
                set: { value in workspaceSettings.updateNavigator { $0.showHiddenFiles = value } }
            ))
            GlobPatternList(
                patterns: $patterns,
                selection: $selection,
                addPattern: { patterns.append(GlobPattern(value: "")) },
                removePatterns: { removed in
                    let ids = removed ?? selection
                    patterns.removeAll { ids.contains($0.id) }
                    selection.subtract(ids)
                },
                emptyMessage: "No Exclusion Patterns"
            )
            .accessibilityIdentifier("NavigatorExclusionPatterns")
        } header: {
            Text("Navigator")
        } footer: {
            Text(LocalizedStringKey(
                "Hide more files from the project navigator. `*.o` matches names anywhere; `build/` matches "
                + "folders only; a pattern with `/` inside, like `docs/*.png`, matches paths from the project root. "
                + "Search and Open Quickly are not affected."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear { patterns = settings.navigator.excludedPatterns.map { GlobPattern(value: $0) } }
        .onChange(of: patterns) { _, newValue in
            let values = newValue.map(\.value).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            workspaceSettings.updateNavigator { $0.excludedPatterns = values }
        }
        .onChange(of: settings.navigator.excludedPatterns) { _, newValue in
            // Reflect edits made to settings.json as text, keeping rows being typed.
            let current = patterns.map(\.value).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard current != newValue else { return }
            patterns = newValue.map { GlobPattern(value: $0) }
        }
    }
}
