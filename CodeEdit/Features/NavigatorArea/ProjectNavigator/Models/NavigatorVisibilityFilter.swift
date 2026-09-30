//
//  NavigatorVisibilityFilter.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/30/26.
//

import Foundation

/// Decides which files the project navigator lists: dotfiles are hidden unless
/// ``NavigatorSettings/showHiddenFiles`` is on, and ``NavigatorSettings/excludedPatterns`` hide more.
///
/// This only affects display. The workspace file manager still tracks every file, so search,
/// Open Quickly, and source control see hidden files.
struct NavigatorVisibilityFilter: Equatable {
    var settings: NavigatorSettings
    /// The workspace root that pattern paths are relative to.
    var rootURL: URL

    /// Whether the navigator lists a file or folder.
    func isVisible(_ url: URL, isFolder: Bool) -> Bool {
        let name = url.lastPathComponent
        if !settings.showHiddenFiles && name.hasPrefix(".") {
            return false
        }
        guard !settings.excludedPatterns.isEmpty else { return true }
        let relativePath = relativePath(of: url)
        return !settings.excludedPatterns.contains {
            Self.pattern($0, matchesName: name, relativePath: relativePath, isFolder: isFolder)
        }
    }

    /// Matches one exclusion pattern using `fnmatch` rules.
    static func pattern(_ rawPattern: String, matchesName name: String, relativePath: String, isFolder: Bool) -> Bool {
        var pattern = rawPattern.trimmingCharacters(in: .whitespaces)
        if pattern.hasSuffix("/") {
            guard isFolder else { return false }
            pattern.removeLast()
        }
        if pattern.hasPrefix("/") {
            pattern.removeFirst()
        }
        guard !pattern.isEmpty else { return false }
        if pattern.contains("/") {
            return fnmatch(pattern, relativePath, FNM_PATHNAME) == 0
        }
        return fnmatch(pattern, name, 0) == 0
    }

    private func relativePath(of url: URL) -> String {
        let root = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : url.lastPathComponent
    }
}
