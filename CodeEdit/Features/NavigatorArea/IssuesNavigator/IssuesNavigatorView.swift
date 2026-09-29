//
//  IssuesNavigatorView.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 22/09/2026.
//

import SwiftUI

/// The Issues navigator tab: compiler diagnostics collected while running `cmake --build`,
/// merged with diagnostics published by running language servers (for example clangd).
///
/// A slim status header shows error and warning counts (plus build progress while a CMake
/// build is running), the list is grouped by file, and a bottom filter bar narrows the
/// displayed issues. Clicking an entry opens the file at the reported line.
struct IssuesNavigatorView: View {
    @EnvironmentObject private var workspace: WorkspaceDocument
    @Service private var lspService: LSPService

    @State private var filter = ""

    private var buildController: CMakeBuildController? {
        workspace.cmakeBuildController
    }

    /// Build diagnostics merged with language server diagnostics.
    private var allDiagnostics: [CMakeBuildDiagnostic] {
        WorkspaceDiagnostics.all(in: workspace, store: lspService.diagnosticsStore)
    }

    var body: some View {
        VStack(spacing: 0) {
            statusHeader
            Divider()
            if allDiagnostics.isEmpty {
                CEContentUnavailableView(
                    "No Issues",
                    description: "Issues are collected when a CMake project is built"
                        + " or published by a language server."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DiagnosticsListView(diagnostics: allDiagnostics, filter: filter)
            }
            filterBar
        }
    }

    // MARK: - Status header

    @ViewBuilder private var statusHeader: some View {
        HStack(spacing: 8) {
            Label("\(errorCount)", systemImage: "xmark.octagon.fill")
                .foregroundStyle(Color.red)
            Label("\(warningCount)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.yellow)
            if buildController?.isBuilding == true {
                ProgressView()
                    .controlSize(.small)
                Text(buildController?.statusText ?? "")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(errorCount) errors, \(warningCount) warnings")
    }

    private var errorCount: Int {
        allDiagnostics.filter { $0.severity == .error }.count
    }

    private var warningCount: Int {
        allDiagnostics.filter { $0.severity == .warning }.count
    }

    // MARK: - Filter bar

    @ViewBuilder private var filterBar: some View {
        NavigatorFilterView(
            text: $filter,
            menu: { EmptyView() },
            leadingAccessories: {
                Image(
                    systemName: filter.isEmpty
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill"
                )
                .foregroundStyle(
                    filter.isEmpty
                    ? Color(nsColor: .secondaryLabelColor)
                    : Color(nsColor: .controlAccentColor)
                )
                .padding(.leading, 4)
                .help("Show issues with matching text")
            },
            trailingAccessories: { EmptyView() }
        )
    }
}
