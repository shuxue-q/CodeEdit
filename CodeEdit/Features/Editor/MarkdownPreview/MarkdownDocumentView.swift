//
//  MarkdownDocumentView.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 28.09.26.
//

import AppKit
import SwiftUI

/// Source, rendered preview, or both, for one Markdown document.
struct MarkdownDocumentView: View {
    var editorInstance: EditorInstance
    var codeFile: CodeFileDocument
    var mode: MarkdownPreviewMode

    @EnvironmentObject private var workspace: WorkspaceDocument
    @EnvironmentObject private var editorManager: EditorManager
    @Environment(\.colorScheme)
    private var colorScheme
    @Environment(\.edgeInsets)
    private var edgeInsets

    @AppSettings(\.theme.matchAppearance)
    private var matchAppearance

    @ObservedObject private var themeModel: ThemeModel = .shared

    var body: some View {
        Group {
            switch mode {
            case .source:
                source
            case .preview:
                preview
            case .split:
                HSplitView {
                    source
                    preview
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var source: some View {
        CodeFileView(editorInstance: editorInstance, codeFile: codeFile)
    }

    private var preview: some View {
        previewContent
            .padding(.top, edgeInsets.top)
            .padding(.bottom, StatusBarView.height)
    }

    private var previewContent: some View {
        let fileURL = codeFile.fileURL ?? editorInstance.file.url
        return Group {
            if MarkdownPreviewResources.root == nil {
                missingResources
            } else {
                MarkdownPreviewView(
                    codeFile: codeFile,
                    markdownFile: fileURL,
                    allowedRoot: MarkdownPreviewRoot.directory(for: fileURL, workspace: workspace),
                    isDark: isDark,
                    onOpenFile: openFile
                )
            }
        }
    }

    private var missingResources: some View {
        Text("Markdown preview resources are missing from the app bundle.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isDark: Bool {
        MarkdownPreviewTheme.isDark(
            colorScheme: colorScheme,
            matchAppearance: matchAppearance,
            themeModel: themeModel
        )
    }

    private func openFile(_ url: URL) {
        if let item = workspace.workspaceFileManager?.getFile(url.path, createIfNotFound: true) {
            editorManager.openTab(item: item)
            return
        }
        NSWorkspace.shared.open(url)
    }
}

enum MarkdownPreviewRoot {
    static func directory(for markdownFile: URL, workspace: WorkspaceDocument?) -> URL {
        guard let fileURL = workspace?.fileURL else {
            return markdownFile.deletingLastPathComponent()
        }
        let root = fileURL.standardizedFileURL
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return root
        }
        return root.deletingLastPathComponent()
    }
}

enum MarkdownPreviewTheme {
    static func isDark(colorScheme: ColorScheme, matchAppearance: Bool, themeModel: ThemeModel) -> Bool {
        let theme = resolvedTheme(colorScheme: colorScheme, matchAppearance: matchAppearance, themeModel: themeModel)
        if let theme {
            return theme.appearance == .dark
        }
        return colorScheme == .dark
    }

    private static func resolvedTheme(
        colorScheme: ColorScheme,
        matchAppearance: Bool,
        themeModel: ThemeModel
    ) -> Theme? {
        if matchAppearance {
            let matched = colorScheme == .dark ? themeModel.selectedDarkTheme : themeModel.selectedLightTheme
            return matched ?? themeModel.selectedTheme
        }
        return themeModel.selectedTheme
    }
}
