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
    /// been chosen for this workspace yet.
    private func startDebugging() {
        guard let workspacePath = workspace.fileURL?.path else { return }
        let key = DebugTargetPicker.defaultsKey(for: workspacePath)
        guard let executablePath = UserDefaults.standard.string(forKey: key) else {
            DebugTargetPicker.chooseExecutable(for: key)
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
}

/// Selects the executable a debug session launches.
///
/// The chosen executable path is persisted per workspace in `UserDefaults` under the key
/// `CodeEdit.DebugExecutable.<workspacePath>`. The button label shows the chosen
/// executable's name, or a prompt to pick one.
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

    private var executableName: String? {
        executablePath.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    /// Presents an open panel for choosing the debug executable and persists the selection.
    /// - Parameter defaultsKey: The `UserDefaults` key to store the chosen path under.
    static func chooseExecutable(for defaultsKey: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the executable to debug"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: defaultsKey)
    }
}
