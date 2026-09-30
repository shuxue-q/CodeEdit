//
//  CMakeExecutableTargets.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/30/26.
//

import Foundation

/// An executable a CMake project builds, offered as a run/debug target.
struct CMakeExecutableTarget: Identifiable, Hashable, Sendable {
    let name: String
    /// The built binary, when the build directory has been configured and the target's
    /// artifact location is known. It may not exist until the target is built.
    let artifact: URL?

    var id: String { name }
}

/// Finds executable targets through the CMake File API, falling back to a static scan of
/// `add_executable()` calls before the project has been configured.
///
/// CodeEdit places a `codemodel-v2` query in the build directory before every configure it runs,
/// so CMake writes a reply describing each target and where its binary goes.
enum CMakeExecutableTargets {
    /// Asks CMake to write the codemodel on the next configure of `buildDirectory`.
    static func writeQuery(buildDirectory: URL) {
        let queryDirectory = buildDirectory.appending(path: ".cmake/api/v1/query")
        try? FileManager.default.createDirectory(at: queryDirectory, withIntermediateDirectories: true)
        let query = queryDirectory.appending(path: "codemodel-v2")
        if !FileManager.default.fileExists(atPath: query.path) {
            FileManager.default.createFile(atPath: query.path, contents: Data())
        }
    }

    /// Lists the executable targets of a project. Reads files only; never runs CMake.
    /// - Parameters:
    ///   - sourceDirectory: The workspace's source directory, scanned when no reply exists.
    ///   - buildDirectory: The build directory holding the File API reply.
    ///   - configuration: The preferred configuration for multi-configuration builds.
    static func load(
        sourceDirectory: URL,
        buildDirectory: URL,
        configuration: String?
    ) -> [CMakeExecutableTarget] {
        if let targets = fromReply(buildDirectory: buildDirectory, configuration: configuration) {
            return targets
        }
        return declaredExecutables(sourceDirectory: sourceDirectory).map {
            CMakeExecutableTarget(name: $0, artifact: nil)
        }
    }

    // MARK: - File API reply

    private struct Index: Decodable {
        struct Object: Decodable {
            struct Version: Decodable { let major: Int }
            let kind: String
            let version: Version
            let jsonFile: String
        }
        let objects: [Object]
    }

    private struct Codemodel: Decodable {
        struct Configuration: Decodable {
            struct Target: Decodable {
                let name: String
                let jsonFile: String
            }
            let name: String
            let targets: [Target]
        }
        let configurations: [Configuration]
    }

    private struct Target: Decodable {
        struct Artifact: Decodable { let path: String }
        let name: String
        let type: String
        let artifacts: [Artifact]?
    }

    /// Reads the newest codemodel reply, or returns `nil` when there is none.
    static func fromReply(buildDirectory: URL, configuration: String?) -> [CMakeExecutableTarget]? {
        let replyDirectory = buildDirectory.appending(path: ".cmake/api/v1/reply")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: replyDirectory.path),
              let indexName = names.filter({ $0.hasPrefix("index-") && $0.hasSuffix(".json") }).max(),
              let index: Index = decode(replyDirectory.appending(path: indexName)),
              let object = index.objects.first(where: { $0.kind == "codemodel" && $0.version.major == 2 }),
              let codemodel: Codemodel = decode(replyDirectory.appending(path: object.jsonFile)) else {
            return nil
        }
        let chosen = codemodel.configurations.first { $0.name == configuration }
            ?? codemodel.configurations.first
        guard let chosen else { return [] }
        return chosen.targets.compactMap { reference -> CMakeExecutableTarget? in
            guard let target: Target = decode(replyDirectory.appending(path: reference.jsonFile)),
                  target.type == "EXECUTABLE" else {
                return nil
            }
            let artifact = target.artifacts?.first.map {
                CMakeConfigureOptions.resolve($0.path, against: buildDirectory)
            }
            return CMakeExecutableTarget(name: target.name, artifact: artifact)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func decode<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Static scan

    /// Directories never scanned for list files: build trees and dependency checkouts.
    private static let skippedDirectories: Set<String> = [
        ".git", ".codeedit", "build", "out", "cmake-build-debug", "cmake-build-release", "node_modules", "_deps"
    ]

    /// Names of literal `add_executable(<name> …)` calls in the project's `CMakeLists.txt` files.
    /// Imported and alias executables are skipped; names built from variables are ignored.
    static func declaredExecutables(sourceDirectory: URL, maximumFiles: Int = 500) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var names: Set<String> = []
        var visited = 0
        for case let url as URL in enumerator {
            if skippedDirectories.contains(url.lastPathComponent)
                || FileManager.default.fileExists(atPath: url.appending(path: "CMakeCache.txt").path) {
                enumerator.skipDescendants()
                continue
            }
            guard url.lastPathComponent == "CMakeLists.txt",
                  let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            names.formUnion(executableNames(in: contents))
            visited += 1
            if visited >= maximumFiles { break }
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Extracts target names from `add_executable()` calls in one list file.
    static func executableNames(in listFile: String) -> [String] {
        let pattern = #"(?im)^[ \t]*add_executable[ \t]*\([ \t\r\n]*([A-Za-z0-9_.+\-]+)([^)]*)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(listFile.startIndex..., in: listFile)
        return regex.matches(in: listFile, range: range).compactMap { match in
            guard let nameRange = Range(match.range(at: 1), in: listFile),
                  let restRange = Range(match.range(at: 2), in: listFile) else { return nil }
            let rest = listFile[restRange].uppercased()
            let words = rest.split(whereSeparator: \.isWhitespace)
            if words.contains("IMPORTED") || words.contains("ALIAS") { return nil }
            return String(listFile[nameRange])
        }
    }
}
