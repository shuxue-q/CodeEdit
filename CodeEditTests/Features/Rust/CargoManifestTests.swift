//
//  CargoManifestTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation
import Testing
@testable import CodeEdit

@Suite
struct CargoManifestTests {
    /// OmniExam's `rust/Cargo.toml`.
    static let workspaceManifest = """
    [workspace]
    resolver = "2"
    members = ["omniexam_typst"]

    [profile.release]
    # staticlib 链进 omniexam_core
    opt-level = 3
    lto = "thin"
    codegen-units = 16
    panic = "unwind"
    """

    /// A trimmed copy of OmniExam's `rust/omniexam_typst/Cargo.toml`.
    static let packageManifest = """
    [package]
    name = "omniexam_typst"
    version = "0.1.0"
    edition = "2024"
    publish = false
    description = "OmniExam 的 Typst 排版内核"

    [lib]
    crate-type = ["staticlib", "rlib"]

    [[bin]]
    name = "omniexam_typst_cli"
    path = "src/bin/omniexam_typst_cli.rs"

    [features]
    default = ["fonts"]
    fonts = []
    pdf = ["dep:typst-pdf"]

    [dependencies]
    typst = "=0.15.1"
    typst-pdf = { version = "=0.15.1", optional = true }
    local = { path = "../local" }
    shared = { workspace = true }
    remote = { git = "https://example.com/r.git", tag = "v1" }

    [target.'cfg(windows)'.dependencies]
    winapi = "0.3"

    [dev-dependencies]
    png = "0.17"

    [build-dependencies]
    cc = "1"
    """

    private func write(_ files: [String: String], in root: URL) throws {
        for (path, contents) in files {
            let url = root.appending(path: path)
            let folder = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Manifest

    @Test
    func readsPackageMetadataTargetsFeaturesAndDependencies() {
        let manifest = CargoManifest.parse(Self.packageManifest)
        #expect(manifest.parseErrors.isEmpty)
        #expect(manifest.packageName == "omniexam_typst")
        #expect(manifest.version == "0.1.0")
        #expect(manifest.edition == "2024")
        #expect(!manifest.publish)
        #expect(manifest.library?.crateTypes == ["staticlib", "rlib"])
        #expect(manifest.declaredTargets.map(\.name) == ["omniexam_typst_cli"])
        #expect(manifest.defaultFeatures == ["fonts"])
        #expect(manifest.namedFeatures.map(\.name) == ["fonts", "pdf"])

        let dependencies = Dictionary(uniqueKeysWithValues: manifest.dependencies.map { ($0.name, $0) })
        #expect(dependencies["typst"]?.source == .registry("=0.15.1"))
        #expect(dependencies["typst-pdf"]?.isOptional == true)
        #expect(dependencies["local"]?.source == .path("../local"))
        #expect(dependencies["shared"]?.source == .workspace)
        #expect(dependencies["remote"]?.source == .git(url: "https://example.com/r.git", reference: "v1"))
        #expect(dependencies["winapi"]?.platform == "cfg(windows)")
        #expect(dependencies["png"]?.kind == .development)
        #expect(dependencies["cc"]?.kind == .build)
    }

    @Test
    func readsWorkspaceAndProfiles() {
        let manifest = CargoManifest.parse(Self.workspaceManifest)
        #expect(manifest.isWorkspace)
        #expect(manifest.workspaceMembers == ["omniexam_typst"])
        #expect(manifest.resolver == "2")
        let release = manifest.profiles.first { $0.name == "release" }
        #expect(release?.optLevel == "3")
        #expect(release?.lto == "thin")
        #expect(release?.codegenUnits == 16)
        #expect(release?.summary == "opt-level 3, lto thin, panic unwind, codegen-units 16")
    }

    @Test
    func readsInheritedPackageKeys() {
        let manifest = CargoManifest.parse("""
        [package]
        name = "member"
        version.workspace = true
        edition = { workspace = true }
        """)
        #expect(manifest.inheritedKeys == ["version", "edition"])
        #expect(manifest.version == nil)
    }

    @Test
    func profileArgumentsSelectTheProfile() {
        #expect(CargoProfile(name: "dev").cargoArguments.isEmpty)
        #expect(CargoProfile(name: "release").cargoArguments == ["--release"])
        #expect(CargoProfile(name: "dist").cargoArguments == ["--profile", "dist"])
    }

    // MARK: - Targets and roots

    @Test
    func discoversTargetsFromTheLayout() throws {
        try withTempDir { root in
            try write([
                "Cargo.toml": Self.packageManifest,
                "src/lib.rs": "",
                "src/main.rs": "",
                "src/bin/omniexam_typst_cli.rs": "",
                "src/bin/extra.rs": "",
                "examples/render.rs": "",
                "examples/multi/main.rs": "",
                "tests/golden.rs": "",
                "benches/speed.rs": "",
                "build.rs": ""
            ], in: root)
            let package = try #require(CargoPackage.load(manifest: root.appending(path: "Cargo.toml")))
            #expect(package.targets(of: .library).first?.name == "omniexam_typst")
            #expect(package.targets(of: .library).first?.crateTypes == ["staticlib", "rlib"])
            // The declared bin keeps its place; `src/main.rs` adds a bin named after the package.
            #expect(package.targets(of: .binary).map(\.name) == ["omniexam_typst_cli", "omniexam_typst", "extra"])
            #expect(package.targets(of: .example).map(\.name) == ["multi", "render"])
            #expect(package.targets(of: .test).map(\.name) == ["golden"])
            #expect(package.targets(of: .bench).map(\.name) == ["speed"])
            #expect(package.targets(of: .buildScript).count == 1)
        }
    }

    @Test
    func loadsAWorkspaceRootWithGlobMembersAndToolchainFile() throws {
        try withTempDir { root in
            try write([
                "rust/Cargo.toml": """
                [workspace]
                members = ["crates/*", "tool"]
                exclude = ["crates/old"]

                [profile.dist]
                inherits = "release"
                """,
                "rust/crates/a/Cargo.toml": "[package]\nname = \"a\"\n[features]\nfast = []\n",
                "rust/crates/a/src/lib.rs": "",
                "rust/crates/b/Cargo.toml": "[package]\nname = \"b\"\n",
                "rust/crates/b/src/main.rs": "",
                "rust/crates/old/Cargo.toml": "[package]\nname = \"old\"\n",
                "rust/tool/Cargo.toml": "[package]\nname = \"tool\"\n",
                "rust/tool/examples/demo.rs": "",
                "rust/rust-toolchain.toml": """
                [toolchain]
                channel = "1.97.1"
                components = ["rust-src"]
                targets = ["aarch64-apple-darwin", "x86_64-pc-windows-msvc"]
                """
            ], in: root)
            let manifest = root.appending(path: "rust/Cargo.toml")
            let cargoRoot = try #require(CargoRoot.load(manifest: manifest, within: root))
            #expect(cargoRoot.isWorkspace)
            #expect(cargoRoot.packages.map(\.name) == ["a", "b", "tool"])
            #expect(cargoRoot.profiles.map(\.name) == ["dev", "release", "test", "bench", "dist"])
            #expect(cargoRoot.toolchainFile?.channel == "1.97.1")
            #expect(cargoRoot.toolchainFile?.components == ["rust-src"])
            #expect(cargoRoot.toolchainFile?.targets.count == 2)
            #expect(cargoRoot.runnableTargets.map(\.title) == ["b", "demo (example)"])
            #expect(cargoRoot.selectableFeatures == ["a/fast"])
            #expect(cargoRoot.runnableTargets.first?.cargoArguments == ["--package", "b", "--bin", "b"])
        }
    }

    @Test
    func rootManifestsSkipWorkspaceMembers() throws {
        try withTempDir { root in
            try write([
                "rust/Cargo.toml": "[workspace]\nmembers = [\"core\"]\n",
                "rust/core/Cargo.toml": "[package]\nname = \"core\"\n",
                "tools/helper/Cargo.toml": "[package]\nname = \"helper\"\n"
            ], in: root)
            let roots = CargoProject.rootManifests(in: root).map { $0.deletingLastPathComponent().lastPathComponent }
            #expect(roots == ["rust", "helper"])
        }
    }

    // MARK: - Toolchain file

    @Test
    func readsLegacyAndTOMLToolchainFiles() throws {
        let legacy = RustToolchainFile.parse("nightly-2026-01-01\n", url: URL(filePath: "/x/rust-toolchain"))
        #expect(legacy.channel == "nightly-2026-01-01")
        let toml = RustToolchainFile.parse(
            "[toolchain]\nchannel = \"stable\"\nprofile = \"minimal\"\n",
            url: URL(filePath: "/x/rust-toolchain")
        )
        #expect(toml.channel == "stable")
        #expect(toml.profile == "minimal")
    }

    @Test
    func findsTheNearestToolchainFileWithinTheWorkspace() throws {
        try withTempDir { root in
            try write(["rust/rust-toolchain.toml": "[toolchain]\nchannel = \"1.97.1\"\n", "rust/crate/x": ""], in: root)
            let nearest = RustToolchainFile.nearest(to: root.appending(path: "rust/crate"), within: root)
            #expect(nearest?.channel == "1.97.1")
            #expect(RustToolchainFile.nearest(to: root, within: root) == nil)
        }
    }
}
