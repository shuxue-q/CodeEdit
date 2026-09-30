//
//  VersionControlPane.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/30/26.
//

import SwiftUI

/// The project editor's Version Control section: repository summary and the `.gitignore` editor.
struct VersionControlPane: View {
    @ObservedObject var sourceControlManager: SourceControlManager
    let gitignore: ProjectTextFile
    let openInTab: (ProjectTextFile) -> Void

    @State private var isRefreshing = false

    var body: some View {
        Form {
            Section {
                if sourceControlManager.isGitRepository {
                    repositoryInfo
                } else {
                    Text("This folder is not a Git repository.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("Repository")
                    Spacer()
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    }
                    Button("Refresh") { Task { await refresh() } }
                        .disabled(isRefreshing)
                }
            }

            Section {
                ProjectTextFileEditor(file: gitignore) { openInTab(gitignore) }
                    .frame(minHeight: 200)
            } header: {
                Text(".gitignore")
            } footer: {
                Text("Paths matching these rules are not tracked by Git. Saving writes the file in the project root.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("ProjectEditorVersionControl")
        .task { await refresh() }
    }

    @ViewBuilder private var repositoryInfo: some View {
        LabeledContent("Branch") {
            HStack(spacing: 6) {
                Text(sourceControlManager.currentBranch?.name ?? "Detached HEAD")
                    .textSelection(.enabled)
                let unsynced = sourceControlManager.numberOfUnsyncedCommits
                if unsynced.ahead > 0 || unsynced.behind > 0 {
                    Text("↑\(unsynced.ahead) ↓\(unsynced.behind)")
                        .foregroundStyle(.secondary)
                        .help("Commits ahead of and behind the upstream branch")
                }
            }
        }
        if sourceControlManager.remotes.isEmpty {
            LabeledContent("Remote", value: "None")
        } else {
            ForEach(sourceControlManager.remotes, id: \.name) { remote in
                LabeledContent(sourceControlManager.remotes.count == 1 ? "Remote" : "Remote “\(remote.name)”") {
                    Text(remote.fetchLocation)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help("\(remote.name): \(remote.fetchLocation)")
                }
            }
        }
        LabeledContent("Status", value: statusSummary)
    }

    private var statusSummary: String {
        let files = sourceControlManager.changedFiles
        guard !files.isEmpty else { return "No changes" }
        var counts: [String: Int] = [:]
        for file in files {
            counts[Self.statusName(file.anyStatus()), default: 0] += 1
        }
        let staged = files.filter(\.isStaged).count
        var parts = counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .map { "\($0.value) \($0.key)" }
        if staged > 0 { parts.append("\(staged) staged") }
        return parts.joined(separator: ", ")
    }

    private static func statusName(_ status: GitStatus) -> String {
        switch status {
        case .modified, .fileTypeChange: "modified"
        case .untracked: "untracked"
        case .added: "added"
        case .deleted: "deleted"
        case .renamed: "renamed"
        case .copied: "copied"
        case .unmerged: "unmerged"
        case .none: "unchanged"
        }
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        try? await sourceControlManager.validate()
        guard sourceControlManager.isGitRepository else { return }
        await sourceControlManager.refreshCurrentBranch()
        await sourceControlManager.refreshAllChangedFiles()
        await sourceControlManager.refreshNumberOfUnsyncedCommits()
        try? await sourceControlManager.refreshRemotes()
    }
}
