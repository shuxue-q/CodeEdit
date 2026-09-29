//
//  MarkdownPreview.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 28.09.26.
//

import Foundation
import CodeEditLanguages

/// How a Markdown document is shown in the editor.
enum MarkdownPreviewMode: String, CaseIterable, Identifiable {
    case source
    case preview
    case split

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source:
            return "Source"
        case .preview:
            return "Preview"
        case .split:
            return "Split"
        }
    }

    var help: String {
        switch self {
        case .source:
            return "Show Markdown Source"
        case .preview:
            return "Render Markdown"
        case .split:
            return "Show Markdown Source and Preview"
        }
    }
}

/// Per-tab Markdown preview mode. Kept separate from ``EditorInstance`` so cursor updates do not
/// refresh the preview chrome.
final class MarkdownPreviewModel: ObservableObject {
    @Published var mode: MarkdownPreviewMode = .source
}

/// Detects Markdown documents that can switch between source and a rendered preview.
enum MarkdownPreview {
    static let extensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn"]

    static func isMarkdown(_ codeFile: CodeFileDocument) -> Bool {
        if codeFile.getLanguage().id == .markdown {
            return true
        }
        return isMarkdownURL(codeFile.fileURL)
    }

    static func isMarkdownURL(_ url: URL?) -> Bool {
        guard let extensionName = url?.pathExtension.lowercased() else { return false }
        return extensions.contains(extensionName)
    }
}
