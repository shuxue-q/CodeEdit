//
//  DebugToolbarView.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/21/26.
//

import SwiftUI

/// The debug session controls shown in the debugger panel's bottom toolbar: start/stop,
/// execution control (continue, pause, step over/into/out), and executable target selection.
struct DebugToolbarView: View {
    @EnvironmentObject private var workspace: WorkspaceDocument
    @ObservedObject private var debugService: DebugService = .shared

    var body: some View {
        HStack(spacing: 8) {
            DebugTargetPicker()
            Divider()

            switch debugService.sessionState {
            case .inactive:
                Button {
                    startDebugging()
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.plain)
                .help("Start Debugging")
                .accessibilityIdentifier("DebugStart")
            case .launching:
                ProgressView()
                    .controlSize(.small)
                    .help("Launching debug session")
            case .running, .paused:
                Button {
                    Task { await debugService.stopDebugging() }
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.plain)
                .help("Stop Debugging")
                .accessibilityIdentifier("DebugStop")
            }

            Divider()

            Button {
                Task { await debugService.resume() }
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.plain)
            .disabled(debugService.sessionState != .paused)
            .help("Continue")

            Button {
                Task { await debugService.pause() }
            } label: {
                Image(systemName: "pause.fill")
            }
            .buttonStyle(.plain)
            .disabled(debugService.sessionState != .running)
            .help("Pause")

            Button {
                Task { await debugService.stepOver() }
            } label: {
                Image(systemName: "arrowshape.turn.up.right")
            }
            .buttonStyle(.plain)
            .disabled(debugService.sessionState != .paused)
            .help("Step Over")

            Button {
                Task { await debugService.stepInto() }
            } label: {
                Image(systemName: "arrow.down.to.line")
            }
            .buttonStyle(.plain)
            .disabled(debugService.sessionState != .paused)
            .help("Step Into")

            Button {
                Task { await debugService.stepOut() }
            } label: {
                Image(systemName: "arrow.up.to.line")
            }
            .buttonStyle(.plain)
            .disabled(debugService.sessionState != .paused)
            .help("Step Out")

            Spacer()
        }
    }

    // MARK: - Session Control

    /// Starts a debug session for the selected executable, prompting for one if none has
    /// been chosen for this workspace yet. In CMake workspaces the run settings from the project
    /// editor take precedence.
    private func startDebugging() {
        guard let workspacePath = workspace.fileURL?.path else { return }
        if let store = workspace.cmakeProjectSettings, store.settings.run.hasExecutable {
            Task { await startDebugging(with: store) }
            return
        }
        let key = DebugTargetPicker.defaultsKey(for: workspacePath)
        guard let executablePath = UserDefaults.standard.string(forKey: key) else {
            if let store = workspace.cmakeProjectSettings {
                store.settings.run.customExecutable = DebugTargetPicker.chooseExecutablePath(
                    startingAt: store.configureOptions.buildDirectory
                ) ?? store.settings.run.customExecutable
            } else {
                DebugTargetPicker.chooseExecutable(for: key)
            }
            return
        }
        Task {
            try? await debugService.startDebugging(
                executable: URL(fileURLWithPath: executablePath),
                arguments: [],
                workingDirectory: URL(fileURLWithPath: workspacePath),
                workspace: workspace
            )
        }
    }

    /// Launches the run target configured in the project editor.
    private func startDebugging(with store: CMakeProjectSettingsStore) async {
        guard let launch = await store.resolveLaunchConfiguration(),
              FileManager.default.isExecutableFile(atPath: launch.executable.path(percentEncoded: false)) else {
            let name = store.settings.run.targetName ?? store.settings.run.customExecutable ?? "The run target"
            debugService.appendConsole(
                category: "error",
                text: "\(name) has no built executable yet. Build the project, then start debugging again."
            )
            debugService.showDebugArea()
            return
        }
        try? await debugService.startDebugging(
            executable: launch.executable,
            arguments: launch.arguments,
            workingDirectory: launch.workingDirectory,
            environment: launch.environment,
            workspace: workspace
        )
    }
}

/// Selects the executable a debug session launches.
///
/// In CMake workspaces the choice is the run target of the project editor, stored in
/// `.codeedit/cmake-settings.json`. Elsewhere the chosen executable path is persisted per
/// workspace in `UserDefaults` under the key `CodeEdit.DebugExecutable.<workspacePath>`.
/// The label shows the chosen executable's name, or a prompt to pick one.
struct DebugTargetPicker: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    /// The chosen executable path, mirrored from `UserDefaults` so the label refreshes.
    @State private var executablePath: String?

    /// Builds the `UserDefaults` key storing the executable path for a workspace.
    /// - Parameter workspacePath: The absolute path of the workspace directory.
    /// - Returns: The defaults key for that workspace.
    static func defaultsKey(for workspacePath: String) -> String {
        "CodeEdit.DebugExecutable.\(workspacePath)"
    }

    private var defaultsKey: String? {
        guard let workspacePath = workspace.fileURL?.path else { return nil }
        return Self.defaultsKey(for: workspacePath)
    }

    var body: some View {
        if let store = workspace.cmakeProjectSettings {
            CMakeRunTargetMenu(store: store, fallbackName: executableName) {
                openRunSettings(store)
            }
            .onAppear {
                executablePath = defaultsKey.flatMap { UserDefaults.standard.string(forKey: $0) }
            }
        } else {
            Button {
                guard let defaultsKey else { return }
                Self.chooseExecutable(for: defaultsKey)
                executablePath = UserDefaults.standard.string(forKey: defaultsKey)
            } label: {
                Label(executableName ?? "Choose Target", systemImage: "hammer")
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Select the executable to debug")
            .accessibilityIdentifier("DebugTargetPicker")
            .onAppear {
                executablePath = defaultsKey.flatMap { UserDefaults.standard.string(forKey: $0) }
            }
        }
    }

    private var executableName: String? {
        executablePath.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    /// Opens the workspace root's project editor on its Run / Debug pane.
    private func openRunSettings(_ store: CMakeProjectSettingsStore) {
        guard let rootURL = workspace.workspaceFileManager?.folderUrl,
              let root = workspace.workspaceFileManager?.getFile(rootURL.path) else { return }
        store.selectedPane = .run
        workspace.editorManager?.openTab(item: root)
    }

    /// Presents an open panel for choosing the debug executable and persists the selection.
    /// - Parameter defaultsKey: The `UserDefaults` key to store the chosen path under.
    static func chooseExecutable(for defaultsKey: String) {
        guard let path = chooseExecutablePath() else { return }
        UserDefaults.standard.set(path, forKey: defaultsKey)
    }

    /// Presents an open panel for choosing an executable.
    /// - Returns: The chosen path, or `nil` when the panel was cancelled.
    static func chooseExecutablePath(startingAt directory: URL? = nil) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory
        panel.message = "Choose the executable to debug"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }
}

/// The debug target menu of a CMake workspace: executable targets, a custom executable, and a
/// shortcut to the run settings.
private struct CMakeRunTargetMenu: View {
    @Bindable var store: CMakeProjectSettingsStore
    /// Shown when no run target is configured but an executable was chosen before.
    let fallbackName: String?
    let editRunSettings: () -> Void

    var body: some View {
        Menu {
            if store.executableTargets.isEmpty {
                Text("No Executable Targets")
            }
            ForEach(store.executableTargets) { target in
                Toggle(target.name, isOn: Binding {
                    store.settings.run.customExecutable == nil && store.settings.run.targetName == target.name
                } set: { _ in
                    store.settings.run.targetName = target.name
                    store.settings.run.customExecutable = nil
                })
            }
            Divider()
            Button("Choose Executable…") {
                let buildDirectory = store.configureOptions.buildDirectory
                if let path = DebugTargetPicker.chooseExecutablePath(startingAt: buildDirectory) {
                    store.settings.run.customExecutable = path
                }
            }
            Button("Edit Run Settings…", action: editRunSettings)
        } label: {
            Label(title, systemImage: "hammer")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("Select the executable to debug")
        .accessibilityIdentifier("DebugTargetPicker")
        .onAppear { store.refreshExecutableTargets() }
    }

    private var title: String {
        let run = store.settings.run
        if let custom = run.customExecutable, !custom.isEmpty {
            return URL(fileURLWithPath: custom).lastPathComponent
        }
        return run.targetName ?? fallbackName ?? "Choose Target"
    }
}
