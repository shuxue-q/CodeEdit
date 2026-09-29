//
//  MarkdownPreviewAssetResolver.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 28.09.26.
//

import Foundation

/// Resolves a Markdown link or image reference to a file inside the workspace.
enum MarkdownPreviewAssetResolver {
    /// Returns a local file for `reference`, or `nil` when the reference is remote, empty, or
    /// escapes `allowedRoot`.
    static func localFile(reference: String, markdownFile: URL, allowedRoot: URL) -> URL? {
        guard let relative = RelativeReference(reference) else { return nil }
        let base = relative.fromWorkspaceRoot ? allowedRoot : markdownFile.deletingLastPathComponent()
        let candidate = base.appending(path: relative.path).standardizedFileURL
        return containedFile(candidate, root: allowedRoot)
    }

    /// A file that exists inside `root` after resolving symlinks. Directories are rejected.
    static func containedFile(_ candidate: URL, root: URL) -> URL? {
        let file = candidate.resolvingSymlinksInPath().standardizedFileURL
        let rootURL = root.resolvingSymlinksInPath().standardizedFileURL
        guard isInside(file: file, root: rootURL) else { return nil }
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return nil
        }
        return file
    }

    private static func isInside(file: URL, root: URL) -> Bool {
        let fileParts = file.pathComponents
        let rootParts = root.pathComponents
        guard fileParts.count >= rootParts.count else { return false }
        return Array(fileParts.prefix(rootParts.count)) == rootParts
    }
}

private struct RelativeReference {
    var path: String
    var fromWorkspaceRoot: Bool

    init?(_ reference: String) {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("//") else { return nil }
        if let scheme = URL(string: trimmed)?.scheme, !scheme.isEmpty { return nil }
        let withoutFragment = trimmed.split(separator: "#", maxSplits: 1).first.map(String.init) ?? trimmed
        let withoutQuery = withoutFragment.split(separator: "?", maxSplits: 1).first.map(String.init) ?? withoutFragment
        let decoded = withoutQuery.removingPercentEncoding ?? withoutQuery
        if decoded.hasPrefix("/") {
            path = String(decoded.dropFirst())
            fromWorkspaceRoot = true
        } else {
            path = decoded
            fromWorkspaceRoot = false
        }
        guard !path.isEmpty else { return nil }
    }
}
