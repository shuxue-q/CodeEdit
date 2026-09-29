//
//  MarkdownPreviewResources.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 28.09.26.
//

import Foundation

/// Locates the vendored Markdown preview page inside the app bundle.
///
/// Xcode copies this folder without keeping `fonts/` or `languages/`. The preview page
/// requests KaTeX fonts and extra grammars by those flat file names.
enum MarkdownPreviewResources {
    private static let pageName = "markdown-preview-index.html"
    private static let cachedRoot: URL? = locate()

    static var root: URL? { cachedRoot }

    static var indexURL: URL? {
        URL(string: "\(MarkdownPreviewScheme.name)://\(MarkdownPreviewScheme.bundleHost)/\(pageName)")
    }

    private static func locate() -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        guard let enumerator = FileManager.default.enumerator(
            at: resources,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }
        while let url = enumerator.nextObject() as? URL {
            if url.lastPathComponent == pageName {
                return url.deletingLastPathComponent()
            }
        }
        return nil
    }
}

enum MarkdownPreviewScheme {
    static let name = "cemd"
    static let bundleHost = "bundle"
    static let assetHost = "asset"

    static func reference(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "ref" }?
            .value
    }
}
