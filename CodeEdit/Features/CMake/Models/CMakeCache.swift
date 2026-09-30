//
//  CMakeCache.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/17/26.
//

import Foundation

/// Reads identity fields from a `CMakeCache.txt` so CodeEdit can tell whether a build
/// directory was configured for the current source tree.
///
/// A leftover or copied cache (for example after a project was renamed or moved) still
/// contains `CMAKE_HOME_DIRECTORY` / `CMAKE_CACHEFILE_DIR` for the original tree. CMake
/// then refuses to build, reporting that the cache directory does not match. Callers
/// should reconfigure after ``invalidateConfiguration(at:)`` rather than invoking
/// `cmake --build` against that cache.
enum CMakeCache {
    /// Whether `buildDirectory` already has a cache produced for `sourceDirectory`.
    ///
    /// - Parameters:
    ///   - sourceDirectory: The workspace source directory CMake should use as `CMAKE_HOME_DIRECTORY`.
    ///   - buildDirectory: The directory that should contain `CMakeCache.txt`.
    /// - Returns: `true` only when a readable cache names this source, and when
    ///   `CMAKE_CACHEFILE_DIR` is present it also names this build directory.
    static func isConfigured(sourceDirectory: URL, buildDirectory: URL) -> Bool {
        let cacheFile = buildDirectory.appending(path: "CMakeCache.txt")
        guard FileManager.default.fileExists(atPath: cacheFile.path) else { return false }
        guard let entries = readEntries(at: cacheFile) else { return false }
        guard let home = entries["CMAKE_HOME_DIRECTORY"], !home.isEmpty else { return false }
        guard samePath(home, sourceDirectory) else { return false }
        if let cacheDirectory = entries["CMAKE_CACHEFILE_DIR"], !cacheDirectory.isEmpty {
            return samePath(cacheDirectory, buildDirectory)
        }
        return true
    }

    /// Removes CMake's configuration metadata from `buildDirectory` so the next configure
    /// is not blocked by a foreign or corrupt cache.
    ///
    /// Deletes `CMakeCache.txt`, `CMakeFiles/`, and `compile_commands.json`. Object files
    /// and libraries are left in place; CMake overwrites what it needs. Individual delete
    /// failures are ignored — a subsequent configure surfaces a real CMake error if the
    /// tree is still unusable.
    /// - Parameter buildDirectory: The CMake binary directory to reset.
    static func invalidateConfiguration(at buildDirectory: URL) {
        let fileManager = FileManager.default
        for name in ["CMakeCache.txt", "CMakeFiles", "compile_commands.json"] {
            try? fileManager.removeItem(at: buildDirectory.appending(path: name))
        }
    }

    /// Whether `directory` contains a `compile_commands.json` that is safe to hand to clangd
    /// for `sourceDirectory`.
    ///
    /// A database with no sibling cache is treated as a standalone export. A database next
    /// to a cache is used only when that cache was produced for this source tree.
    static func isUsableCompilationDatabase(in directory: URL, sourceDirectory: URL) -> Bool {
        let database = directory.appending(path: "compile_commands.json")
        guard FileManager.default.fileExists(atPath: database.path) else { return false }
        let cacheFile = directory.appending(path: "CMakeCache.txt")
        guard FileManager.default.fileExists(atPath: cacheFile.path) else { return true }
        return isConfigured(sourceDirectory: sourceDirectory, buildDirectory: directory)
    }

    // MARK: - Cache file

    /// The `KEY → VALUE` entries of the cache in `buildDirectory`, or `nil` when it has none.
    static func entries(in buildDirectory: URL) -> [String: String]? {
        readEntries(at: buildDirectory.appending(path: "CMakeCache.txt"))
    }

    /// Parses `KEY:TYPE=VALUE` entries from a CMake cache file, skipping comments.
    private static func readEntries(at cacheFile: URL) -> [String: String]? {
        guard let contents = try? String(contentsOf: cacheFile, encoding: .utf8) else { return nil }
        var entries: [String: String] = [:]
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = rawLine
            if line.hasSuffix("\r") { line.removeLast() }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") { continue }
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            let keyAndType = trimmed[..<equals]
            guard let colon = keyAndType.firstIndex(of: ":") else { continue }
            let key = String(keyAndType[..<colon])
            guard !key.isEmpty else { continue }
            entries[key] = String(trimmed[trimmed.index(after: equals)...])
        }
        return entries
    }

    /// Compares a cache path value with a file URL, ignoring trailing slashes and resolving
    /// symlinks so `/var` and `/private/var` match.
    static func samePath(_ path: String, _ url: URL) -> Bool {
        normalizedPath(path) == normalizedPath(url.path)
    }

    private static func normalizedPath(_ path: String) -> String {
        var result = URL(filePath: path).standardizedFileURL.resolvingSymlinksInPath().path
        while result.count > 1 && result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}
