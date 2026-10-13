//
//  CargoProjectTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation
import Testing
@testable import CodeEdit

/// Reading `Cargo.toml` files and finding the Cargo projects rust-analyzer has to be told about.
@Suite
struct CargoProjectTests {
    // MARK: - Manifest

    @Test
    func parsesPackageName() {
        let manifest = CargoManifest.parse("""
        [package]
        name = "omniexam_typst" # the crate
        version = "0.1.0"

        [dependencies]
        name = "not the package"
        """)
        #expect(manifest.packageName == "omniexam_typst")
        #expect(!manifest.isWorkspace)
    }

    @Test
    func parsesWorkspaceMembersAndExcludeAcrossLines() {
        let manifest = CargoManifest.parse("""
        [workspace]
        resolver = "2"
        members = [
            "crates/a", # first
            "crates/b",
        ]
        exclude = ["crates/old"]

        [profile.release]
        lto = "thin"
        """)
        #expect(manifest.isWorkspace)
        #expect(manifest.packageName == nil)
        #expect(manifest.workspaceMembers == ["crates/a", "crates/b"])
        #expect(manifest.workspaceExclude == ["crates/old"])
    }

    @Test
    func workspaceSubtableMakesAWorkspace() {
        let manifest = CargoManifest.parse("[workspace.dependencies]\nserde = \"1\"\n")
        #expect(manifest.isWorkspace)
    }

    @Test
    func hashInsideAStringIsNotAComment() {
        let manifest = CargoManifest.parse("[package]\nname = \"a#b\"\n")
        #expect(manifest.packageName == "a#b")
    }

    // MARK: - Discovery

    private func write(_ files: [String: String], in root: URL) throws {
        for (path, contents) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func relativePaths(_ urls: [URL], in root: URL) -> [String] {
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        return urls.map { $0.resolvingSymlinksInPath().path.replacingOccurrences(of: base, with: "") }
    }

    private static let package = "[package]\nname = \"crate\"\nversion = \"0.1.0\"\n"

    @Test
    func rootManifestNeedsNoLinkedProjects() throws {
        try withTempDir { root in
            try write(["Cargo.toml": Self.package, "tools/helper/Cargo.toml": Self.package], in: root)
            #expect(CargoProject.hasRootManifest(root))
            #expect(CargoProject.linkedProjects(in: root).isEmpty)
        }
    }

    @Test
    func nestedWorkspaceIsLinkedWithoutItsMembers() throws {
        try withTempDir { root in
            try write([
                "pubspec.yaml": "name: app\n",
                "rust/Cargo.toml": "[workspace]\nmembers = [\"omniexam_typst\"]\n",
                "rust/omniexam_typst/Cargo.toml": Self.package,
                "rust/omniexam_typst/src/lib.rs": ""
            ], in: root)
            #expect(relativePaths(CargoProject.linkedProjects(in: root), in: root) == ["rust/Cargo.toml"])
        }
    }

    @Test
    func excludedWorkspacePathIsLinkedOnItsOwn() throws {
        try withTempDir { root in
            try write([
                "rust/Cargo.toml": "[workspace]\nmembers = [\"a\"]\nexclude = [\"legacy\"]\n",
                "rust/a/Cargo.toml": Self.package,
                "rust/legacy/Cargo.toml": Self.package
            ], in: root)
            #expect(
                relativePaths(CargoProject.linkedProjects(in: root), in: root)
                    == ["rust/Cargo.toml", "rust/legacy/Cargo.toml"]
            )
        }
    }

    @Test
    func independentCratesAreAllLinkedShallowestFirst() throws {
        try withTempDir { root in
            try write([
                "native/core/Cargo.toml": Self.package,
                "cli/Cargo.toml": Self.package,
                "native/ffi/Cargo.toml": Self.package
            ], in: root)
            #expect(
                relativePaths(CargoProject.linkedProjects(in: root), in: root)
                    == ["cli/Cargo.toml", "native/core/Cargo.toml", "native/ffi/Cargo.toml"]
            )
        }
    }

    @Test
    func buildOutputToolCachesAndHiddenFoldersAreSkipped() throws {
        try withTempDir { root in
            try write([
                "target/package/Cargo.toml": Self.package,
                "build/x/Cargo.toml": Self.package,
                ".dart_tool/y/Cargo.toml": Self.package,
                "node_modules/z/Cargo.toml": Self.package,
                ".claude/worktrees/copy/rust/Cargo.toml": Self.package,
                "rust/Cargo.toml": Self.package
            ], in: root)
            #expect(relativePaths(CargoProject.discoverManifests(in: root), in: root) == ["rust/Cargo.toml"])
        }
    }

    @Test
    func searchStopsAtTheDepthLimit() throws {
        try withTempDir { root in
            try write([
                "a/b/c/Cargo.toml": Self.package,
                "a/b/c/d/Cargo.toml": Self.package
            ], in: root)
            #expect(CargoProject.maxSearchDepth == 3)
            #expect(relativePaths(CargoProject.discoverManifests(in: root), in: root) == ["a/b/c/Cargo.toml"])
        }
    }

    @Test
    func symlinkedDirectoriesAreNotFollowed() throws {
        try withTempDir { root in
            try write(["real/crate/Cargo.toml": Self.package], in: root)
            try FileManager.default.createSymbolicLink(
                at: root.appending(path: "alias"),
                withDestinationURL: root.appending(path: "real")
            )
            #expect(relativePaths(CargoProject.discoverManifests(in: root), in: root) == ["real/crate/Cargo.toml"])
        }
    }

    @Test
    func emptyFolderHasNoProjects() throws {
        try withTempDir { root in
            #expect(CargoProject.linkedProjects(in: root).isEmpty)
        }
    }
}
