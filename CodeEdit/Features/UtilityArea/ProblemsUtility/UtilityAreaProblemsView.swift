//
//  UtilityAreaProblemsView.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/14/26.
//

import SwiftUI
import CodeEditSourceEditor

/// The problems panel: compiler diagnostics collected while running `cmake --build`, merged
/// with diagnostics published by running language servers (for example clangd).
///
/// Entries are grouped by file and ordered by severity; clicking an entry opens the file in
/// the editor at the reported line. Only the panel content lives here — starting and stopping
/// builds stays with the existing task controls, no separate build UI is added.
struct UtilityAreaProblemsView: View {
    @EnvironmentObject private var utilityAreaViewModel: UtilityAreaViewModel
    @EnvironmentObject private var workspace: WorkspaceDocument
    @Service private var lspService: LSPService

    /// Scroll anchor at the bottom of the live build log, used to keep it pinned to the end.
    private static let buildLogAnchorID = "ProblemsBuildLogBottom"

    private var buildController: CMakeBuildController? {
        workspace.cmakeBuildController
    }

    /// Diagnostics published by the workspace's language servers.
    private var lspDiagnostics: [CMakeBuildDiagnostic] {
        guard let workspacePath = workspace.fileURL?.absolutePath else { return [] }
        return WorkspaceDiagnostics.merged(
            cmake: [],
            lsp: lspService.diagnosticsStore.diagnostics(for: workspacePath)
        )
    }

    /// Build diagnostics merged with language server diagnostics.
    private var allDiagnostics: [CMakeBuildDiagnostic] {
        WorkspaceDiagnostics.all(in: workspace, store: lspService.diagnosticsStore)
    }

    var body: some View {
        UtilityAreaTabView(model: utilityAreaViewModel.tabViewModel) { _ in
            ZStack {
                HStack { Spacer() }

                if let buildController, buildController.isBuilding {
                    buildLog(buildController)
                } else if let buildController {
                    if allDiagnostics.isEmpty {
                        emptyState(buildController)
                    } else {
                        DiagnosticsListView(diagnostics: allDiagnostics)
                    }
                } else if !lspDiagnostics.isEmpty {
                    DiagnosticsListView(diagnostics: lspDiagnostics)
                } else {
                    CEContentUnavailableView(
                        "No Problems Detected",
                        description: "Problems are collected when a CMake project is built"
                            + " or published by a language server."
                    )
                }
            }
            .paneToolbar {
                statusBar
            }
        }
    }

    // MARK: - Content

    /// Live output streamed from the running build, shown while a build is in progress
    /// so the user can follow the process instead of watching a spinner.
    @ViewBuilder
    private func buildLog(_ buildController: CMakeBuildController) -> some View {
        if buildController.lastBuildLog.isEmpty {
            // The process produces no output until configure/build messages arrive.
            ProgressView(buildController.statusText)
                .controlSize(.small)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(buildController.lastBuildLog)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .id(Self.buildLogAnchorID)
                }
                .accessibilityIdentifier("ProblemsBuildLog")
                .onAppear {
                    proxy.scrollTo(Self.buildLogAnchorID, anchor: .bottom)
                }
                .onChange(of: buildController.lastBuildLog) {
                    proxy.scrollTo(Self.buildLogAnchorID, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func emptyState(_ buildController: CMakeBuildController) -> some View {
        switch buildController.outcome {
        case .success:
            CEContentUnavailableView(
                "No Problems Found",
                systemImage: "checkmark.circle"
            )
        case .failed:
            CEContentUnavailableView(
                "Build Failed",
                description: "No compiler diagnostics were captured; see the build output for details."
            )
        case .cancelled:
            CEContentUnavailableView("Build Stopped")
        case .none:
            CEContentUnavailableView(
                "No Problems Detected",
                description: "Build the project to collect compiler diagnostics."
            )
        }
    }

    // MARK: - Toolbar

    @ViewBuilder private var statusBar: some View {
        HStack(spacing: 8) {
            let errorCount = allDiagnostics.filter { $0.severity == .error }.count
            let warningCount = allDiagnostics.filter { $0.severity == .warning }.count
            if buildController != nil || !allDiagnostics.isEmpty {
                Label(
                    "\(errorCount) errors, \(warningCount) warnings",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(errorCount > 0 ? Color.red : Color.secondary)
                if buildController?.isBuilding == true {
                    ProgressView()
                        .controlSize(.small)
                    Text(buildController?.statusText ?? "")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let buildController, !buildController.diagnostics.isEmpty {
                Button {
                    buildController.clearDiagnostics()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear problems")
                .accessibilityIdentifier("ProblemsClear")
            }
        }
    }
}
