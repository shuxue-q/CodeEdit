//
//  ProjectInventoryTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation
import Testing
@testable import CodeEdit

@Suite
struct ProjectInventoryTests {
    @Test
    func findsTheComponentsOfAHybridWorkspace() throws {
        try withTempDir { root in
            try HybridProjectFixture.write(in: root)
            let inventory = ProjectInventory.scan(workspace: root)
            let summary = inventory.components.map { "\($0.kind.rawValue) \($0.relativePath) \($0.role.rawValue)" }
            #expect(summary == [
                "flutterApp . primary",
                "flutterPackage third_party/flutter_math_fork thirdParty",
                "cmakeProject . primary",
                "platformRunner windows generated",
                "cargoWorkspace rust primary"
            ])
            #expect(inventory.toolchains == [.flutter, .cmake, .cargo])
            #expect(inventory.isHybrid)
            #expect(inventory.flutter?.name == "omniexam_app")
            #expect(inventory.cargoRoots.map(\.name) == ["omniexam_typst"])
        }
    }

    @Test
    func detectsBuildConnections() throws {
        try withTempDir { root in
            try HybridProjectFixture.write(in: root)
            let inventory = ProjectInventory.scan(workspace: root)
            let links = inventory.links.map { "\($0.source) \($0.summary) \($0.target) via \($0.evidence)" }
            #expect(links.contains("flutterApp:. builds cmakeProject:. via hook/build.dart"))
            #expect(links.contains("cmakeProject:. builds cargoWorkspace:rust via cpp/CMakeLists.txt"))
            #expect(links.contains(
                "flutterApp:. depends on flutterPackage:third_party/flutter_math_fork via pubspec.yaml"
            ))
        }
    }

    @Test
    func listsConfigurationFilesByToolchain() throws {
        try withTempDir { root in
            try HybridProjectFixture.write(in: root)
            let files = ProjectInventory.scan(workspace: root).configurationFiles
            let paths = Dictionary(grouping: files, by: \.toolchain).mapValues { $0.map(\.relativePath) }
            #expect(paths[.flutter] == ["pubspec.yaml", "analysis_options.yaml", "hook/build.dart"])
            #expect(paths[.cmake] == ["CMakeLists.txt", "CMakePresets.json"])
            #expect(paths[.cargo] == [
                "rust/Cargo.toml", "rust/omniexam_typst/Cargo.toml", "rust/omniexam_typst/build.rs",
                "rust/rust-toolchain.toml"
            ])
        }
    }

    @Test
    func singleToolchainWorkspacesAreNotHybrid() throws {
        try withTempDir { root in
            let manifest = root.appending(path: "Cargo.toml")
            try "[package]\nname = \"solo\"\n".write(to: manifest, atomically: true, encoding: .utf8)
            let inventory = ProjectInventory.scan(workspace: root)
            #expect(inventory.toolchains == [.cargo])
            #expect(!inventory.isHybrid)
            #expect(inventory.components.map(\.kind) == [.cargoPackage])
        }
    }

    @Test
    func relevantFileEventsTriggerRescans() {
        #expect(ProjectInventoryModel.isRelevant("/w/pubspec.yaml"))
        #expect(ProjectInventoryModel.isRelevant("/w/rust/omniexam_typst/Cargo.toml"))
        #expect(ProjectInventoryModel.isRelevant("/w/.dart_tool/package_config.json"))
        #expect(ProjectInventoryModel.isRelevant("/w/.codeedit/cargo-settings.json"))
        #expect(ProjectInventoryModel.isRelevant("/w/rust/.cargo/config.toml"))
        #expect(!ProjectInventoryModel.isRelevant("/w/lib/main.dart"))
        #expect(!ProjectInventoryModel.isRelevant("/w/build/macos/CMakeLists.txt"))
        #expect(!ProjectInventoryModel.isRelevant("/w/rust/target/debug/build/x/Cargo.toml"))
        #expect(!ProjectInventoryModel.isRelevant("/w/typst/config.toml"))
    }
}
