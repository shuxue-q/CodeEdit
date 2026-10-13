//
//  CargoProject.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

/// Finds the Cargo projects in a workspace folder so `rust-analyzer` can load the ones it would
/// not find on its own.
///
/// `rust-analyzer` discovers a `Cargo.toml` at the workspace root (and in the folders of open files,
/// one level up). A repository that keeps its crates below the root, such as a Flutter app with a
/// Cargo workspace in `rust/`, needs the manifests passed as `linkedProjects`. Discovery only reads
/// the file system; it never runs `cargo`. It can touch many directories, so call it off the main actor.
enum CargoProject {
    /// How many directory levels below the workspace root are searched for manifests.
    static let maxSearchDepth = 3

    /// The most directories one search visits, so a huge folder cannot stall a server start.
    static let maxVisitedDirectories = 4_000

    /// Directory names never searched: build output, tool caches, and dependency trees. Hidden
    /// directories (`.git`, `.claude`, `.build`) are skipped as well.
    static let skippedDirectoryNames: Set<String> = ["target", "build", ".dart_tool", "node_modules"]

    /// Whether `directory` holds a `Cargo.toml` itself.
    /// - Parameter directory: The folder to check.
    static func hasRootManifest(_ directory: URL) -> Bool {
        let manifest = directory.appending(path: CargoManifest.fileName)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: manifest.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    /// The manifests to hand `rust-analyzer` as `linkedProjects` for a workspace.
    ///
    /// Empty when the workspace root has a `Cargo.toml`, which the server finds by itself. Otherwise
    /// every manifest found by ``discoverManifests(in:)``, except those covered by a workspace manifest:
    /// a `[workspace]` manifest loads the packages below its directory, so linking them again would only
    /// load them twice. A path in the workspace's `exclude` list is not covered.
    /// - Parameter workspace: The workspace folder.
    /// - Returns: Absolute manifest URLs, shallowest first.
    static func linkedProjects(in workspace: URL) -> [URL] {
        let workspace = workspace.standardizedFileURL
        guard !hasRootManifest(workspace) else { return [] }
        let manifests = discoverManifests(in: workspace).compactMap { url in
            CargoManifest.read(at: url).map { (url: url, manifest: $0) }
        }
        let workspaces = manifests.filter(\.manifest.isWorkspace)
        return manifests
            .filter { candidate in
                !workspaces.contains { covers($0.url, $0.manifest, candidate.url) }
            }
            .map(\.url)
    }

    /// The manifests `cargo` commands run from: the workspace root's manifest when it has one, and
    /// every discovered manifest that no `[workspace]` manifest covers. Third-party folders are
    /// included; callers decide what to do with them.
    /// - Parameter workspace: The workspace folder.
    /// - Returns: Absolute manifest URLs, shallowest first.
    static func rootManifests(in workspace: URL) -> [URL] {
        let workspace = workspace.standardizedFileURL
        var urls = discoverManifests(in: workspace)
        if hasRootManifest(workspace) {
            urls.insert(workspace.appending(path: CargoManifest.fileName), at: 0)
        }
        let manifests = urls.compactMap { url in
            CargoManifest.read(at: url).map { (url: url, manifest: $0) }
        }
        let workspaces = manifests.filter(\.manifest.isWorkspace)
        return manifests
            .filter { candidate in
                !workspaces.contains { covers($0.url, $0.manifest, candidate.url) }
            }
            .map(\.url)
    }

    /// Finds `Cargo.toml` files below `workspace`, breadth first, at most ``maxSearchDepth`` levels deep.
    ///
    /// Skips ``skippedDirectoryNames``, hidden directories, and symbolic links. The workspace root's
    /// own manifest is not included.
    /// - Parameter workspace: The workspace folder.
    /// - Returns: Manifest URLs ordered by depth, then by path.
    static func discoverManifests(in workspace: URL) -> [URL] {
        let fileManager = FileManager.default
        var found: [URL] = []
        var level = [workspace.standardizedFileURL]
        var visited = 0

        for _ in 0..<maxSearchDepth {
            var nextLevel: [URL] = []
            for directory in level {
                for child in subdirectories(of: directory, fileManager: fileManager) {
                    visited += 1
                    guard visited <= maxVisitedDirectories else { return sorted(found) }
                    if hasRootManifest(child) {
                        found.append(child.appending(path: CargoManifest.fileName))
                    }
                    nextLevel.append(child)
                }
            }
            level = nextLevel.sorted { $0.path < $1.path }
        }
        return sorted(found)
    }

    // MARK: - Private

    /// The searchable subdirectories of `directory`, sorted by name.
    private static func subdirectories(of directory: URL, fileManager: FileManager) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let children = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return children
            .filter { child in
                guard let values = try? child.resourceValues(forKeys: Set(keys)),
                      values.isDirectory == true, values.isSymbolicLink != true else {
                    return false
                }
                return !skippedDirectoryNames.contains(child.lastPathComponent)
            }
            .map(\.standardizedFileURL)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Whether the workspace manifest at `workspaceURL` loads the manifest at `candidate`: it lies in
    /// the workspace's directory or below it, and not in a directory the workspace excludes.
    static func covers(_ workspaceURL: URL, _ workspace: CargoManifest, _ candidate: URL) -> Bool {
        guard candidate != workspaceURL else { return false }
        let root = workspaceURL.deletingLastPathComponent().path
        let candidateDirectory = candidate.deletingLastPathComponent().path
        guard candidateDirectory.hasPrefix(root + "/") else { return false }
        let relative = String(candidateDirectory.dropFirst(root.count + 1))
        return !workspace.workspaceExclude.contains { excluded in
            let excluded = excluded.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return relative == excluded || relative.hasPrefix(excluded + "/")
        }
    }

    private static func sorted(_ urls: [URL]) -> [URL] {
        urls.sorted { lhs, rhs in
            let depths = (lhs.pathComponents.count, rhs.pathComponents.count)
            return depths.0 == depths.1 ? lhs.path < rhs.path : depths.0 < depths.1
        }
    }
}
