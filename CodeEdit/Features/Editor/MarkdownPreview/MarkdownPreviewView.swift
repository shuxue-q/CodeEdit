//
//  MarkdownPreviewView.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 28.09.26.
//

import SwiftUI
import WebKit

/// Rendered Markdown. The page, math fonts, and diagram runtime are bundled with the app.
struct MarkdownPreviewView: NSViewRepresentable {
    var codeFile: CodeFileDocument
    var markdownFile: URL
    var allowedRoot: URL
    var isDark: Bool
    var onOpenFile: (URL) -> Void

    func makeCoordinator() -> MarkdownPreviewController {
        MarkdownPreviewController()
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.makeWebView(markdownFile: markdownFile, allowedRoot: allowedRoot)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(
            document: codeFile,
            markdownFile: markdownFile,
            allowedRoot: allowedRoot,
            isDark: isDark,
            onOpenFile: onOpenFile
        )
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: MarkdownPreviewController) {
        coordinator.invalidate()
    }
}
