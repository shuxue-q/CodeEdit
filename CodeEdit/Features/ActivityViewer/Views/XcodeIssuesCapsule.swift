//
//  XcodeIssuesCapsule.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/17/26.
//

import SwiftUI

/// Warnings badge capsule replicating Xcode's `[ ⚠ n ]` control.
/// Hidden while the workspace has no warnings.
struct XcodeWarningsCapsule: View {
    @Service private var lspService: LSPService
    var workspace: WorkspaceDocument?

    var body: some View {
        IssuesCapsuleContent(
            workspace: workspace,
            store: lspService.diagnosticsStore,
            severity: .warning,
            color: Color(nsColor: .systemYellow),
            help: "Show Warnings (Problems)"
        )
    }
}

/// Errors badge capsule replicating Xcode's `[ ⚠ n ]` error control.
/// Hidden while the workspace has no errors.
struct XcodeErrorsCapsule: View {
    @Service private var lspService: LSPService
    var workspace: WorkspaceDocument?

    var body: some View {
        IssuesCapsuleContent(
            workspace: workspace,
            store: lspService.diagnosticsStore,
            severity: .error,
            color: Color(nsColor: .systemRed),
            help: "Show Errors (Problems)"
        )
    }
}

private struct IssuesCapsuleContent: View {
    var workspace: WorkspaceDocument?
    var store: LSPDiagnosticsStore
    let severity: CMakeBuildDiagnostic.Severity
    let color: Color
    let help: String

    private var issueCount: Int {
        guard let workspace else { return 0 }
        return WorkspaceDiagnostics.navigable(
            WorkspaceDiagnostics.all(in: workspace, store: store)
        )
        .filter { $0.severity == severity }
        .count
    }

    var body: some View {
        if issueCount > 0 {
            XcodeCapsuleContainer(horizontalPadding: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(color)

                    Text("\(issueCount)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .contentShape(Capsule())
            }
            .onTapGesture {
                openProblemsPanel()
            }
            .help(help)
            .accessibilityValue("\(issueCount)")
        }
    }

    private func openProblemsPanel() {
        if let utilityArea = workspace?.utilityAreaModel {
            utilityArea.selectedTab = .problems
            if utilityArea.isCollapsed {
                utilityArea.isCollapsed = false
            }
        }
    }
}
