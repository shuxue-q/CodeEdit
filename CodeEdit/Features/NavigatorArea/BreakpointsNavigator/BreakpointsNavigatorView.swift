//
//  BreakpointsNavigatorView.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 22/09/2026.
//

import SwiftUI
import CodeEditSourceEditor
import CodeEditSymbols

/// The Breakpoints navigator tab: every source breakpoint in ``BreakpointStore``,
/// grouped by file.
///
/// Sections show the file name with its workspace-relative path; rows show the
/// breakpoint marker, the 1-based line number, and a snippet of the line's code
/// (loaded lazily, off the main actor). Rows for files that no longer exist are
/// dimmed like Xcode's stale breakpoints and cannot be jumped to. Clicking a row
/// opens the file at that line. The bottom bar holds the global breakpoint
/// enable switch, a menu with bulk actions, and a text filter.
struct BreakpointsNavigatorView: View {
    @EnvironmentObject private var workspace: WorkspaceDocument
    @ObservedObject private var store = BreakpointStore.shared

    @State private var filter = ""
    /// Line snippets keyed by `"path:line"`, loaded off the main actor.
    @State private var snippets: [String: String] = [:]
    /// Paths whose file could not be read (deleted or moved since the breakpoint was set).
    @State private var staleFiles: Set<String> = []

    /// A single breakpoint row: an absolute file path and a 0-based line index.
    private struct BreakpointItem: Identifiable, Hashable {
        let filePath: String
        let line: Int

        var id: String { "\(filePath):\(line)" }
    }

    /// The breakpoints of one file, sorted by line.
    private struct FileGroup: Identifiable {
        let path: String
        var entries: [BreakpointItem]

        var id: String { path }
    }

    var body: some View {
        VStack(spacing: 0) {
            if groups.isEmpty {
                CEContentUnavailableView(
                    "No Breakpoints",
                    description: "Click a line number in the editor gutter to add a breakpoint."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredGroups.isEmpty {
                CEContentUnavailableView(
                    "No Filter Results",
                    description: "No breakpoints match the current filter."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                breakpointList
            }
            bottomBar
        }
        .task(id: store.breakpoints) {
            await loadSnippets()
        }
    }

    // MARK: - List

    private var breakpointList: some View {
        List {
            ForEach(filteredGroups) { group in
                Section {
                    ForEach(group.entries) { entry in
                        breakpointRow(entry)
                    }
                } header: {
                    HStack(spacing: 4) {
                        Text(URL(fileURLWithPath: group.path).lastPathComponent)
                            .font(.headline)
                            .lineLimit(1)
                        Text(displayPath(group.path))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                    .accessibilityIdentifier("BreakpointsGroupHeader")
                }
            }
        }
        .listStyle(.inset)
    }

    private func breakpointRow(_ entry: BreakpointItem) -> some View {
        let isStale = staleFiles.contains(entry.filePath)
        return HStack(spacing: 6) {
            breakpointImage(isStale: isStale)
            Text("Line \(entry.line + 1)")
                .font(.system(size: 12, weight: .medium))
            if let snippet = snippets[entry.id], !snippet.isEmpty {
                Text(snippet)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .foregroundStyle(isStale ? .secondary : .primary)
        .contentShape(Rectangle())
        .onTapGesture {
            open(entry)
        }
        .contextMenu {
            Button("Jump to Breakpoint") {
                open(entry)
            }
            .disabled(isStale)
            Divider()
            Button("Delete Breakpoint") {
                store.toggle(filePath: entry.filePath, line: entry.line)
                syncBreakpoints(files: [entry.filePath])
            }
        }
        .accessibilityIdentifier("BreakpointEntry")
    }

    /// The Xcode-style breakpoint arrow: the filled, blue marker from the gutter
    /// (`NSColor.systemBlue`) when active, outlined and grayed when the global
    /// switch is off or the file is stale.
    private func breakpointImage(isStale: Bool) -> some View {
        let active = store.isEnabled && !isStale
        return (active ? Image.breakpointFill : Image.breakpoint)
            .foregroundStyle(active ? Color(nsColor: .systemBlue) : Color(nsColor: .secondaryLabelColor))
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        NavigatorFilterView(
            text: $filter,
            menu: { enableButton },
            leadingAccessories: { filterIcon },
            trailingAccessories: { actionsMenu }
        )
    }

    /// Global breakpoint enable switch, mirroring Xcode's breakpoint navigator button.
    private var enableButton: some View {
        Button {
            store.isEnabled.toggle()
            syncBreakpoints(files: Array(store.breakpoints.keys))
        } label: {
            if store.isEnabled {
                Image.breakpointFill
                    .foregroundStyle(Color(nsColor: .systemBlue))
            } else {
                Image.breakpoint
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 18, alignment: .center)
        .help(store.isEnabled ? "Deactivate Breakpoints" : "Activate Breakpoints")
        .accessibilityLabel("Toggle Breakpoints")
    }

    private var filterIcon: some View {
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
        .help("Show breakpoints with matching file or code")
    }

    private var actionsMenu: some View {
        Menu {
            Button("Delete All Breakpoints", role: .destructive) {
                let files = Array(store.breakpoints.keys)
                store.clearAll()
                syncBreakpoints(files: files)
            }
            .disabled(store.breakpoints.isEmpty)
        } label: {}
        .background {
            Image(systemName: "ellipsis.circle")
                .accessibilityHidden(true)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(maxWidth: 18, alignment: .center)
        .help("Breakpoint Actions")
        .accessibilityLabel("Breakpoint Actions")
    }

    // MARK: - Grouping and filtering

    /// All breakpoints grouped by file path, files sorted alphabetically and lines ascending.
    private var groups: [FileGroup] {
        store.breakpoints
            .map { path, lines in
                FileGroup(
                    path: path,
                    entries: lines.sorted().map { BreakpointItem(filePath: path, line: $0) }
                )
            }
            .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }

    /// The groups matching ``filter``: a file match keeps all of its lines, otherwise
    /// only lines whose code snippet matches are kept. Case-insensitive.
    private var filteredGroups: [FileGroup] {
        guard !filter.isEmpty else { return groups }
        return groups.compactMap { group in
            let fileName = URL(fileURLWithPath: group.path).lastPathComponent
            if fileName.localizedCaseInsensitiveContains(filter)
                || group.path.localizedCaseInsensitiveContains(filter) {
                return group
            }
            let entries = group.entries.filter { entry in
                snippets[entry.id]?.localizedCaseInsensitiveContains(filter) ?? false
            }
            return entries.isEmpty ? nil : FileGroup(path: group.path, entries: entries)
        }
    }

    /// The path relative to the workspace folder when possible, the full path otherwise.
    private func displayPath(_ path: String) -> String {
        guard let root = workspace.workspaceFileManager?.folderUrl.path,
              path.hasPrefix(root + "/") else {
            return path
        }
        return String(path.dropFirst(root.count + 1))
    }

    // MARK: - Snippet loading

    /// Reloads line snippets for every breakpoint off the main actor.
    private func loadSnippets() async {
        let breakpoints = store.breakpoints
        let loaded = await Task.detached(priority: .utility) {
            loadBreakpointSnippets(breakpoints)
        }.value
        guard !Task.isCancelled else { return }
        snippets = loaded.snippets
        staleFiles = loaded.staleFiles
    }

    // MARK: - Navigation

    /// Opens the breakpoint's file in the editor and places the cursor on its line.
    /// Stored lines are 0-based; ``CursorPosition`` lines are 1-based.
    private func open(_ entry: BreakpointItem) {
        guard !staleFiles.contains(entry.filePath),
              let file = workspace.workspaceFileManager?.getFile(
                  entry.filePath,
                  createIfNotFound: true
              ) else {
            return
        }
        workspace.editorManager?.openTab(item: file)
        workspace.editorManager?.activeEditor.selectedTab?.cursorPositions = [
            CursorPosition(line: entry.line + 1, column: 1)
        ]
    }

    /// Pushes breakpoint edits to a live debug adapter. Gutter clicks already sync;
    /// the navigator's enable switch, delete, and delete-all do not go through it.
    private func syncBreakpoints(files: [String]) {
        guard DebugService.shared.sessionState != .inactive else { return }
        Task {
            for file in files {
                await DebugService.shared.syncBreakpoints(filePath: file)
            }
        }
    }
}

/// Reads the code at each breakpoint line from disk.
///
/// Files that cannot be read are reported as stale; lines past the end of an
/// existing file are left without a snippet.
/// - Parameter breakpoints: Breakpoints keyed by absolute file path, lines 0-based.
/// - Returns: Snippets keyed by `"path:line"`, and the set of stale file paths.
private func loadBreakpointSnippets(
    _ breakpoints: [String: Set<Int>]
) -> (snippets: [String: String], staleFiles: Set<String>) {
    var snippets: [String: String] = [:]
    var staleFiles: Set<String> = []
    for (path, lines) in breakpoints {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            staleFiles.insert(path)
            continue
        }
        let contentLines = content.components(separatedBy: .newlines)
        for line in lines where contentLines.indices.contains(line) {
            snippets["\(path):\(line)"] = contentLines[line].trimmingCharacters(in: .whitespaces)
        }
    }
    return (snippets, staleFiles)
}
