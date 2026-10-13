//
//  ProjectTaskCatalogTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation
import Testing
@testable import CodeEdit

@Suite
struct ProjectTaskCatalogTests {
    private func inputs(
        _ settings: FlutterProjectSettings = FlutterProjectSettings()
    ) -> ProjectTaskCatalog.FlutterInputs {
        ProjectTaskCatalog.FlutterInputs(settings: settings, sdkBinDirectory: nil, device: .macOS)
    }

    private let cmake = ProjectTaskCatalog.CMakeInputs(
        projectName: "omniexam",
        buildDirectory: URL(filePath: "/w/build/macos debug"),
        configuration: nil
    )

    @Test
    func generatesFlutterCargoAndCMakeTasks() throws {
        try withTempDir { root in
            try HybridProjectFixture.write(in: root)
            let inventory = ProjectInventory.scan(workspace: root)
            let tasks = ProjectTaskCatalog.tasks(
                inventory: inventory,
                flutter: inputs(),
                cargoSettings: CargoProjectSettings(),
                cmake: cmake
            )
            let commands = Dictionary(uniqueKeysWithValues: tasks.map { ($0.name, $0.command) })
            #expect(commands["Run omniexam_app"] == "flutter --no-wrap run -d 'macos' '--debug'")
            #expect(commands["Build omniexam_app (macOS)"] == "flutter --no-wrap build macos '--debug'")
            #expect(commands["Pub Get"] == "flutter --no-wrap pub get")
            #expect(commands["Build Runner"] == "dart run build_runner build --delete-conflicting-outputs")
            #expect(commands["Cargo Build"] == "cargo build")
            #expect(commands["Cargo Check"] == "cargo check --all-targets")
            #expect(commands["Run omniexam_typst_cli"]
                    == "cargo run '--package' 'omniexam_typst' '--bin' 'omniexam_typst_cli'")
            #expect(commands["Run render (example)"] == "cargo run '--package' 'omniexam_typst' '--example' 'render'")
            #expect(commands["Test omniexam (CTest)"]
                    == "ctest --test-dir '/w/build/macos debug' --output-on-failure")
            #expect(tasks.first { $0.name == "Build omniexam (CMake)" }?.info.action == .cmakeBuild)

            let run = try #require(tasks.first { $0.name == "Run omniexam_app" })
            #expect(run.info.supportsHotReload)
            #expect(run.info.outputParser == .flutter)
            #expect(tasks.first { $0.name == "Cargo Build" }?.workingDirectory == "rust")
            #expect(tasks.first { $0.name == "Cargo Build" }?.info.outputParser == .cargo)
        }
    }

    @Test
    func appliesFlutterSettingsWithQuoting() throws {
        try withTempDir { root in
            try HybridProjectFixture.write(in: root)
            var settings = FlutterProjectSettings()
            settings.buildMode = .profile
            settings.target = "lib/main dev.dart"
            settings.flavor = "staging"
            settings.dartDefines = [
                CMakeProjectSettings.KeyValue(name: "API", value: "https://x/$(id)"),
                CMakeProjectSettings.KeyValue(name: "OFF", value: "1", isEnabled: false)
            ]
            settings.runArguments = "--verbose --route '/home page'"
            let tasks = ProjectTaskCatalog.tasks(
                inventory: ProjectInventory.scan(workspace: root),
                flutter: inputs(settings),
                cargoSettings: CargoProjectSettings(),
                cmake: nil
            )
            let run = try #require(tasks.first { $0.name == "Run omniexam_app" })
            let expected = "flutter --no-wrap run -d 'macos' '--profile' '-t' 'lib/main dev.dart' "
                + "'--flavor' 'staging' '--dart-define=API=https://x/$(id)' '--verbose' '--route' '/home page'"
            #expect(run.command == expected)
            #expect(!run.info.supportsHotReload)
        }
    }

    @Test
    func appliesCargoSettings() throws {
        try withTempDir { root in
            try HybridProjectFixture.write(in: root)
            var settings = CargoProjectSettings()
            var rust = CargoProjectSettings.Root()
            rust.profile = "release"
            rust.features = ["fast"]
            rust.noDefaultFeatures = true
            rust.target = "aarch64-apple-darwin"
            rust.runArguments = "input.typ --out 'a b.pdf'"
            rust.environment = [CMakeProjectSettings.KeyValue(name: "RUST_LOG", value: "debug")]
            settings.roots["rust"] = rust
            let tasks = ProjectTaskCatalog.tasks(
                inventory: ProjectInventory.scan(workspace: root),
                flutter: nil,
                cargoSettings: settings,
                cmake: nil
            )
            let build = try #require(tasks.first { $0.name == "Cargo Build" })
            let expected = "cargo build '--release' '--features' 'fast' '--no-default-features' "
                + "'--target' 'aarch64-apple-darwin'"
            #expect(build.command == expected)
            let run = try #require(tasks.first { $0.name == "Run omniexam_typst_cli" })
            #expect(run.command.hasSuffix("-- 'input.typ' '--out' 'a b.pdf'"))
            #expect(run.environment == ["RUST_LOG": "debug"])
            let example = try #require(tasks.first { $0.name == "Run render (example)" })
            #expect(!example.command.contains(" -- "))
        }
    }

    @Test
    func cmakeTasksAppearOnlyNextToOtherGeneratedTasks() throws {
        try withTempDir { root in
            try "project(solo)\n".write(to: root.appending(path: "CMakeLists.txt"), atomically: true, encoding: .utf8)
            let tasks = ProjectTaskCatalog.tasks(
                inventory: ProjectInventory.scan(workspace: root),
                flutter: nil,
                cargoSettings: CargoProjectSettings(),
                cmake: cmake
            )
            #expect(tasks.isEmpty)
        }
    }

    @Test
    func sdkOverrideQuotesToolPaths() throws {
        try withTempDir { root in
            try HybridProjectFixture.write(in: root)
            let flutter = ProjectTaskCatalog.FlutterInputs(
                settings: FlutterProjectSettings(),
                sdkBinDirectory: URL(filePath: "/opt/flutter sdk/bin"),
                device: .macOS
            )
            let tasks = ProjectTaskCatalog.tasks(
                inventory: ProjectInventory.scan(workspace: root),
                flutter: flutter,
                cargoSettings: CargoProjectSettings(),
                cmake: nil
            )
            #expect(tasks.first { $0.name == "Pub Get" }?.command == "'/opt/flutter sdk/bin/flutter' --no-wrap pub get")
        }
    }

    @Test
    func stableIDsSurviveRegeneration() {
        let info = GeneratedTaskInfo(
            action: .shell,
            toolchain: .cargo,
            role: .build,
            group: "Rust · x",
            componentPath: "rust",
            outputParser: .cargo
        )
        let first = GeneratedTask(name: "Cargo Build", command: "cargo build", workingDirectory: "rust", info: info)
        let second = GeneratedTask(
            name: "Cargo Build",
            command: "cargo build --release",
            workingDirectory: "rust",
            info: info
        )
        #expect(first.id == second.id)
        #expect(first.id != GeneratedTask(name: "Cargo Test", command: "", workingDirectory: "rust", info: info).id)
        let task = first.makeTask()
        #expect(task.id == first.id)
        #expect(task.workingDirectory == "rust")
    }
}
