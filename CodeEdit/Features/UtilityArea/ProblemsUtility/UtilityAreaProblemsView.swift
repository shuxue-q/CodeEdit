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

                if let buildController {
                    if allDiagnostics.isEmpty {
                        emptyState(buildController)
                    } else {
                        diagnosticList(allDiagnostics)
                    }
                } else if !lspDiagnostics.isEmpty {
                    diagnosticList(lspDiagnostics)
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

    @ViewBuilder
    private func emptyState(_ buildController: CMakeBuildController) -> some View {
        if buildController.isBuilding {
            ProgressView(buildController.statusText)
                .controlSize(.small)
        } else {
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
    }

    private func diagnosticList(_ diagnostics: [CMakeBuildDiagnostic]) -> some View {
        List {
            ForEach(fileGroups(diagnostics)) { group in
                Section {
                    ForEach(group.diagnostics) { diagnostic in
                        diagnosticRow(diagnostic)
                            .onTapGesture {
                                open(diagnostic)
                            }
                    }
                } header: {
                    HStack {
                        Text(displayPath(group.path))
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Text(group.summary)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("ProblemsGroupHeader")
                }
            }
        }
        .listStyle(.inset)
    }

    private func diagnosticRow(_ diagnostic: CMakeBuildDiagnostic) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon(for: diagnostic.severity))
                .foregroundStyle(color(for: diagnostic.severity))
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(diagnostic.summary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let location = locationLabel(for: diagnostic) {
                    Text(location)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .accessibilityIdentifier("ProblemsEntry")
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

    // MARK: - Grouping and presentation helpers

    private struct FileGroup: Identifiable {
        let path: String
        var diagnostics: [CMakeBuildDiagnostic]

        var id: String { path }

        var errorCount: Int {
            diagnostics.reduce(0) { $0 + ($1.severity == .error ? 1 : 0) }
        }

        var summary: String {
            let errors = errorCount
            let warnings = diagnostics.count - errors
            switch (errors, warnings) {
            case (0, 0): return ""
            case (0, _): return "\(warnings) warnings"
            case (_, 0): return "\(errors) errors"
            default: return "\(errors) errors, \(warnings) warnings"
            }
        }
    }

    /// Groups diagnostics by printed file path, files with errors first, then alphabetical.
    private func fileGroups(_ diagnostics: [CMakeBuildDiagnostic]) -> [FileGroup] {
        let grouped = Dictionary(grouping: diagnostics) { $0.filePath ?? "(other)" }
        return grouped
            .map { path, entries in
                FileGroup(path: path, diagnostics: entries.sorted {
                    if $0.severity != $1.severity { return $0.severity < $1.severity }
                    return ($0.line ?? 0) < ($1.line ?? 0)
                })
            }
            .sorted {
                if ($0.errorCount > 0) != ($1.errorCount > 0) { return $0.errorCount > 0 }
                return $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
            }
    }

    private func displayPath(_ path: String) -> String {
        guard path != "(other)", let root = workspace.workspaceFileManager?.folderUrl.path else {
            return path
        }
        if path.hasPrefix(root + "/") {
            return String(path.dropFirst(root.count + 1))
        }
        return path
    }

    private func locationLabel(for diagnostic: CMakeBuildDiagnostic) -> String? {
        guard let filePath = diagnostic.filePath else { return nil }
        var label = displayPath(resolve(filePath).path)
        if let line = diagnostic.line {
            label += ":\(line)"
            if let column = diagnostic.column {
                label += ":\(column)"
            }
        }
        return label
    }

    private func icon(for severity: CMakeBuildDiagnostic.Severity) -> String {
        switch severity {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .note: return "info.circle.fill"
        }
    }

    private func color(for severity: CMakeBuildDiagnostic.Severity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .yellow
        case .note: return .secondary
        }
    }

    // MARK: - Navigation

    /// Resolves the path as printed by the compiler: absolute paths are used as-is, relative
    /// paths are tried against the source directory first and then against the build directory.
    private func resolve(_ filePath: String) -> URL {
        WorkspaceDiagnostics.resolvePath(
            filePath,
            sourceDirectory: workspace.workspaceFileManager?.folderUrl,
            configurePreset: workspace.cmakeWorkspace?.configurePreset
        )
    }

    private func open(_ diagnostic: CMakeBuildDiagnostic) {
        WorkspaceDiagnostics.open(diagnostic, workspace: workspace)
    }
}
