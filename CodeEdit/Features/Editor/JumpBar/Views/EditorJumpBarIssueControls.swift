//
//  EditorJumpBarIssueControls.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/17/26.
//

import SwiftUI

/// Previous/next issue walker on the trailing edge of the jump bar.
struct EditorJumpBarIssueControls: View {
    @EnvironmentObject private var workspace: WorkspaceDocument
    @Service private var lspService: LSPService

    var body: some View {
        IssueControlsContent(workspace: workspace, store: lspService.diagnosticsStore)
    }
}

private struct IssueControlsContent: View {
    @ObservedObject var workspace: WorkspaceDocument
    var store: LSPDiagnosticsStore

    private var diagnostics: [CMakeBuildDiagnostic] {
        WorkspaceDiagnostics.navigable(WorkspaceDiagnostics.all(in: workspace, store: store))
    }

    private var canNavigate: Bool {
        !diagnostics.isEmpty
    }

    var body: some View {
        HStack(spacing: 2) {
            Button {
                WorkspaceDiagnostics.jumpToPreviousIssue(workspace: workspace, store: store)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 16, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canNavigate)
            .help("Jump to Previous Issue")

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(canNavigate ? Color(nsColor: .systemIndigo) : .secondary)
                .opacity(canNavigate ? 1 : 0.45)

            Button {
                WorkspaceDiagnostics.jumpToNextIssue(workspace: workspace, store: store)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 16, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canNavigate)
            .help("Jump to Next Issue")
        }
        .opacity(canNavigate ? 1 : 0.55)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Issue Navigation")
    }
}
