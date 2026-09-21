//
//  WorkspaceDiagnostics.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/17/26.
//

import Foundation
import LanguageServerProtocol
import CodeEditSourceEditor

/// Merges CMake build diagnostics with language-server diagnostics and walks them
/// in file/line order for the problems panel and jump bar.
enum WorkspaceDiagnostics {
    /// Combines compiler diagnostics with the latest language-server publish set.
    /// - Parameters:
    ///   - cmake: Diagnostics parsed from the most recent `cmake --build`.
    ///   - lsp: Language-server diagnostics keyed by document URI.
    /// - Returns: A single list, CMake entries first, then LSP conversions that succeed.
    static func merged(
        cmake: [CMakeBuildDiagnostic],
        lsp: [String: [Diagnostic]]
    ) -> [CMakeBuildDiagnostic] {
        let lspEntries = lsp.flatMap { uri, diagnostics in
            diagnostics.compactMap { CMakeBuildDiagnostic(lspDiagnostic: $0, uri: uri) }
        }
        return cmake + lspEntries
    }

    /// Errors and warnings that point at a file, sorted by path then line then column.
    /// Notes are omitted so issue navigation matches Xcode's walker.
    static func navigable(_ diagnostics: [CMakeBuildDiagnostic]) -> [CMakeBuildDiagnostic] {
        diagnostics
            .filter { $0.severity != .note && $0.filePath != nil }
            .sorted(by: isOrderedBefore)
    }

    /// The next navigable issue after `file`/`line`/`column`, wrapping to the first item.
    static func nextIssue(
        afterFile file: String?,
        line: Int,
        column: Int,
        in diagnostics: [CMakeBuildDiagnostic]
    ) -> CMakeBuildDiagnostic? {
        let items = navigable(diagnostics)
        guard !items.isEmpty else { return nil }
        if let index = items.firstIndex(where: { isAfter($0, file: file, line: line, column: column) }) {
            return items[index]
        }
        return items.first
    }

    /// The previous navigable issue before `file`/`line`/`column`, wrapping to the last item.
    static func previousIssue(
        beforeFile file: String?,
        line: Int,
        column: Int,
        in diagnostics: [CMakeBuildDiagnostic]
    ) -> CMakeBuildDiagnostic? {
        let items = navigable(diagnostics)
        guard !items.isEmpty else { return nil }
        if let index = items.lastIndex(where: { isBefore($0, file: file, line: line, column: column) }) {
            return items[index]
        }
        return items.last
    }

    /// Resolves a compiler-printed path against the source directory, then the build directory.
    static func resolvePath(
        _ filePath: String,
        sourceDirectory: URL?,
        configurePreset: CMakePreset?
    ) -> URL {
        let fileManager = FileManager.default
        if filePath.hasPrefix("/") {
            return URL(fileURLWithPath: filePath)
        }
        let sourceRelative = sourceDirectory?.appending(path: filePath)
            ?? URL(fileURLWithPath: filePath)
        if fileManager.fileExists(atPath: sourceRelative.path) {
            return sourceRelative
        }
        let buildDirectory = CMakeCompilationDatabase.buildDirectory(
            sourceDirectory: sourceDirectory ?? URL(fileURLWithPath: "/"),
            configurePreset: configurePreset
        )
        let buildRelative = buildDirectory.appending(path: filePath)
        return fileManager.fileExists(atPath: buildRelative.path) ? buildRelative : sourceRelative
    }

    /// Opens `diagnostic` in the workspace editor at its reported location.
    @MainActor
    static func open(_ diagnostic: CMakeBuildDiagnostic, workspace: WorkspaceDocument) {
        guard let filePath = diagnostic.filePath else { return }
        let resolved = resolvePath(
            filePath,
            sourceDirectory: workspace.workspaceFileManager?.folderUrl,
            configurePreset: workspace.cmakeWorkspace?.configurePreset
        )
        guard let file = workspace.workspaceFileManager?.getFile(
            resolved.path,
            createIfNotFound: true
        ) else {
            return
        }
        workspace.editorManager?.openTab(item: file)
        workspace.editorManager?.activeEditor.selectedTab?.cursorPositions = [
            CursorPosition(line: max(diagnostic.line ?? 1, 1), column: max(diagnostic.column ?? 1, 1))
        ]
    }

    /// All diagnostics currently known for `workspace`.
    @MainActor
    static func all(in workspace: WorkspaceDocument, store: LSPDiagnosticsStore) -> [CMakeBuildDiagnostic] {
        let cmake = workspace.cmakeBuildController?.diagnostics ?? []
        let lsp: [String: [Diagnostic]]
        if let path = workspace.fileURL?.absolutePath {
            lsp = store.diagnostics(for: path)
        } else {
            lsp = [:]
        }
        return merged(cmake: cmake, lsp: lsp)
    }

    /// Jumps to the next issue relative to the active editor cursor.
    @MainActor
    static func jumpToNextIssue(workspace: WorkspaceDocument, store: LSPDiagnosticsStore) {
        let diagnostic = nextIssue(
            afterFile: currentFilePath(in: workspace),
            line: currentLine(in: workspace),
            column: currentColumn(in: workspace),
            in: all(in: workspace, store: store)
        )
        if let diagnostic {
            open(diagnostic, workspace: workspace)
        }
    }

    /// Jumps to the previous issue relative to the active editor cursor.
    @MainActor
    static func jumpToPreviousIssue(workspace: WorkspaceDocument, store: LSPDiagnosticsStore) {
        let diagnostic = previousIssue(
            beforeFile: currentFilePath(in: workspace),
            line: currentLine(in: workspace),
            column: currentColumn(in: workspace),
            in: all(in: workspace, store: store)
        )
        if let diagnostic {
            open(diagnostic, workspace: workspace)
        }
    }

    // MARK: - Ordering

    private static func isOrderedBefore(_ lhs: CMakeBuildDiagnostic, _ rhs: CMakeBuildDiagnostic) -> Bool {
        let leftPath = lhs.filePath ?? ""
        let rightPath = rhs.filePath ?? ""
        if leftPath != rightPath {
            return leftPath.localizedStandardCompare(rightPath) == .orderedAscending
        }
        if lhs.line != rhs.line {
            return (lhs.line ?? 0) < (rhs.line ?? 0)
        }
        return (lhs.column ?? 0) < (rhs.column ?? 0)
    }

    private static func isAfter(
        _ diagnostic: CMakeBuildDiagnostic,
        file: String?,
        line: Int,
        column: Int
    ) -> Bool {
        compare(diagnostic, toFile: file, line: line, column: column) == .orderedDescending
    }

    private static func isBefore(
        _ diagnostic: CMakeBuildDiagnostic,
        file: String?,
        line: Int,
        column: Int
    ) -> Bool {
        compare(diagnostic, toFile: file, line: line, column: column) == .orderedAscending
    }

    private static func compare(
        _ diagnostic: CMakeBuildDiagnostic,
        toFile file: String?,
        line: Int,
        column: Int
    ) -> ComparisonResult {
        let diagnosticPath = diagnostic.filePath ?? ""
        let currentPath = file ?? ""
        if diagnosticPath != currentPath {
            return diagnosticPath.localizedStandardCompare(currentPath)
        }
        let diagnosticLine = diagnostic.line ?? 0
        if diagnosticLine != line {
            return diagnosticLine < line ? .orderedAscending : .orderedDescending
        }
        let diagnosticColumn = diagnostic.column ?? 0
        if diagnosticColumn == column { return .orderedSame }
        return diagnosticColumn < column ? .orderedAscending : .orderedDescending
    }

    @MainActor
    private static func currentFilePath(in workspace: WorkspaceDocument) -> String? {
        workspace.editorManager?.activeEditor.selectedTab?.file.url.path
    }

    @MainActor
    private static func currentLine(in workspace: WorkspaceDocument) -> Int {
        workspace.editorManager?.activeEditor.selectedTab?.cursorPositions.first?.start.line ?? 1
    }

    @MainActor
    private static func currentColumn(in workspace: WorkspaceDocument) -> Int {
        workspace.editorManager?.activeEditor.selectedTab?.cursorPositions.first?.start.column ?? 1
    }
}
