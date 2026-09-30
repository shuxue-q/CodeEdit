//
//  DiagnosticsListView.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/22/26.
//

import SwiftUI

/// An Xcode-style grouped diagnostics list shared by navigator tabs and the problems panel.
///
/// Diagnostics are grouped by file, files with errors are sorted first, and each section
/// shows a workspace-relative path header with an error, warning, and note summary. Clicking
/// an entry opens the file in the editor at the reported line.
struct DiagnosticsListView: View {
    @EnvironmentObject private var workspace: WorkspaceDocument

    private let diagnostics: [CMakeBuildDiagnostic]
    private let filter: String

    /// Creates the list.
    /// - Parameters:
    ///   - diagnostics: The merged diagnostics to display.
    ///   - filter: An optional case-insensitive filter matched against the message and file
    ///     path before grouping. Empty (the default) disables filtering.
    init(diagnostics: [CMakeBuildDiagnostic], filter: String = "") {
        self.diagnostics = diagnostics
        self.filter = filter
    }

    var body: some View {
        List {
            ForEach(fileGroups(filteredDiagnostics)) { group in
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

    private var filteredDiagnostics: [CMakeBuildDiagnostic] {
        guard !filter.isEmpty else { return diagnostics }
        return diagnostics.filter {
            $0.message.localizedCaseInsensitiveContains(filter)
                || ($0.filePath?.localizedCaseInsensitiveContains(filter) ?? false)
        }
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
                    .fixedSize(horizontal: false, vertical: true)
                if let location = locationLabel(for: diagnostic) {
                    Text(location)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityIdentifier("ProblemsEntry")
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
            DiagnosticGroupSummary.text(
                errors: diagnostics.reduce(0) { $0 + ($1.severity == .error ? 1 : 0) },
                warnings: diagnostics.reduce(0) { $0 + ($1.severity == .warning ? 1 : 0) },
                notes: diagnostics.reduce(0) { $0 + ($1.severity == .note ? 1 : 0) }
            )
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
            configurePreset: workspace.cmakeWorkspace?.configurePreset,
            buildDirectory: workspace.cmakeProjectSettings?.configureOptions.buildDirectory
        )
    }

    private func open(_ diagnostic: CMakeBuildDiagnostic) {
        WorkspaceDiagnostics.open(diagnostic, workspace: workspace)
    }
}

/// The "1 error, 2 warnings, 1 note" header for a diagnostics file group.
enum DiagnosticGroupSummary {
    static func text(errors: Int, warnings: Int, notes: Int) -> String {
        [
            label(errors, singular: "error", plural: "errors"),
            label(warnings, singular: "warning", plural: "warnings"),
            label(notes, singular: "note", plural: "notes")
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private static func label(_ count: Int, singular: String, plural: String) -> String? {
        switch count {
        case 0:
            return nil
        case 1:
            return "1 \(singular)"
        default:
            return "\(count) \(plural)"
        }
    }
}
