//
//  HybridWorkspaceDocumentTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation
import Testing
@testable import CodeEdit

/// Opens hybrid workspaces through ``WorkspaceDocument`` and checks the wiring end to end:
/// discovery, generated tasks, settings changes, and real tool output becoming problems.
@MainActor
@Suite(.serialized)
struct HybridWorkspaceDocumentTests {
    private func open(_ root: URL) throws -> WorkspaceDocument {
        let workspace = WorkspaceDocument()
        try workspace.read(from: root, ofType: "public.folder")
        return workspace
    }

    private func taskNames(_ workspace: WorkspaceDocument) -> [String] {
        workspace.taskManager?.generatedTasks.map(\.name) ?? []
    }

    private func command(_ name: String, in workspace: WorkspaceDocument) -> String? {
        workspace.taskManager?.generatedTasks.first { $0.name == name }?.command
    }

    @Test
    func openingAHybridWorkspaceGeneratesTasksAndFollowsSettings() async throws {
        try await withTempDir { root in
            try HybridProjectFixture.write(in: root)
            let workspace = try open(root)
            defer { workspace.close() }

            await waitForExpectation(timeout: .seconds(20)) {
                taskNames(workspace).contains("Build omniexam (CMake)")
            } onTimeout: {
                Issue.record("Generated tasks never included the CMake build: \(taskNames(workspace))")
            }
            let names = taskNames(workspace)
            #expect(names.first == "Run omniexam_app")
            #expect(names.contains("Cargo Build"))
            #expect(names.contains("Test omniexam (CTest)"))
            #expect(workspace.projectInventory?.inventory?.isHybrid == true)
            let files = workspace.projectEditorState?.configurationFiles.map(\.displayPath) ?? []
            #expect(files.contains("rust/Cargo.toml"))
            #expect(files.contains(".codeedit/flutter-settings.json"))

            workspace.flutterWorkspace?.settings.value.buildMode = .release
            #expect(command("Run omniexam_app", in: workspace)?.contains("'--release'") == true)

            workspace.projectInventory?.cargoSettings.value.roots["rust"] = {
                var root = CargoProjectSettings.Root()
                root.profile = "release"
                return root
            }()
            #expect(command("Cargo Build", in: workspace) == "cargo build '--release'")

            // A new nested crate appears after a rescan.
            try "[package]\nname = \"helper\"\n".write(
                to: root.appending(path: "tools/helper/Cargo.toml").creatingParentFolder(),
                atomically: true,
                encoding: .utf8
            )
            workspace.projectInventory?.reload()
            await workspace.projectInventory?.waitForReload()
            #expect(taskNames(workspace).contains("Cargo Build helper"))
        }
    }

    /// Writes a crate whose `value()` function has `body`.
    private func writeCrate(at crate: URL, body: String) throws {
        try "[package]\nname = \"demo\"\nversion = \"0.1.0\"\nedition = \"2021\"\n".write(
            to: crate.appending(path: "Cargo.toml").creatingParentFolder(),
            atomically: true,
            encoding: .utf8
        )
        try "pub fn value() -> i32 {\n\(body)\n}\n".write(
            to: crate.appending(path: "src/lib.rs").creatingParentFolder(),
            atomically: true,
            encoding: .utf8
        )
    }

    @Test
    func cargoCheckErrorsBecomeProblems() async throws {
        guard LanguageServerDetector.locateExecutables(["cargo"])["cargo"] != nil else { return }
        Settings.shared.preferences.terminal.shell = .zsh
        try await withTempDir { root in
            let crate = root.appending(path: "rust")
            try writeCrate(at: crate, body: "    let unused = 1;\n    missing")
            let workspace = try open(root)
            defer { workspace.close() }
            await waitForExpectation(timeout: .seconds(20)) {
                taskNames(workspace).contains("Cargo Check")
            } onTimeout: {
                Issue.record("No Cargo Check task: \(taskNames(workspace))")
            }
            let taskManager = try #require(workspace.taskManager)
            taskManager.runGeneratedTask(toolchain: .cargo, role: .check)
            let taskID = try #require(taskManager.selectedTaskID)
            await waitForExpectation(timeout: .seconds(120)) {
                taskManager.taskStatus(taskID: taskID) == .failed
            } onTimeout: {
                Issue.record("cargo check did not fail: \(taskManager.taskStatus(taskID: taskID))")
            }

            let source = crate.appending(path: "src/lib.rs").standardizedFileURL.path
            // The terminal can deliver the last lines just after the exit; wait for the problem.
            await waitForExpectation(timeout: .seconds(5)) {
                WorkspaceDiagnostics.all(in: workspace, store: LSPDiagnosticsStore())
                    .contains { $0.severity == .error && $0.filePath == source }
            } onTimeout: {
                let terminal = taskManager.activeTasks[taskID]?.output?.getBufferAsString() ?? ""
                Issue.record("No error parsed. Terminal: \(terminal)")
            }
            let problems = WorkspaceDiagnostics.all(in: workspace, store: LSPDiagnosticsStore())
            let error = problems.first { $0.severity == .error && $0.filePath == source }
            #expect(error?.line == 3)
            #expect(error?.code == "E0425")

            // rustc reports lints only once names resolve: fix the error and check again. The
            // second run replaces the first run's problems.
            try writeCrate(at: crate, body: "    let unused = 1;\n    2")
            taskManager.runGeneratedTask(toolchain: .cargo, role: .check)
            await waitForExpectation(timeout: .seconds(120)) {
                taskManager.taskStatus(taskID: taskID) == .finished
            } onTimeout: {
                Issue.record("cargo check did not succeed: \(taskManager.taskStatus(taskID: taskID))")
            }
            await waitForExpectation(timeout: .seconds(5)) {
                WorkspaceDiagnostics.all(in: workspace, store: LSPDiagnosticsStore())
                    .contains { $0.severity == .warning && $0.filePath == source && $0.line == 2 }
            } onTimeout: {
                Issue.record("The unused variable warning was not parsed")
            }
            let warnings = WorkspaceDiagnostics.all(in: workspace, store: LSPDiagnosticsStore())
            #expect(!warnings.contains { $0.severity == .error }, "\(warnings.map(\.summary))")
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["HYBRID_REAL_FLUTTER"] != nil))
    func flutterAnalyzeIssuesBecomeProblems() async throws {
        guard let flutter = LanguageServerDetector.locateExecutables(["flutter"])["flutter"] else { return }
        Settings.shared.preferences.terminal.shell = .zsh
        try await withTempDir { root in
            let environment = LanguageServerDetector.userShellEnvironment()
            let created = ToolProcess.run(
                flutter,
                ["create", "--offline", "--template=package", "--project-name", "demo_pkg", "."],
                in: root,
                environment: environment,
                timeout: 180
            )
            try #require(created?.succeeded == true, "flutter create failed: \(created?.errorOutput ?? "")")
            try "int broken() => undefinedName;\n".write(
                to: root.appending(path: "lib/demo_pkg.dart"),
                atomically: true,
                encoding: .utf8
            )
            let workspace = try open(root)
            defer { workspace.close() }
            await waitForExpectation(timeout: .seconds(20)) {
                taskNames(workspace).contains("Analyze demo_pkg")
            } onTimeout: {
                Issue.record("No Analyze task: \(taskNames(workspace))")
            }
            let taskManager = try #require(workspace.taskManager)
            taskManager.runGeneratedTask(toolchain: .flutter, role: .analyze)
            let taskID = try #require(taskManager.selectedTaskID)
            await waitForExpectation(timeout: .seconds(180)) {
                taskManager.taskStatus(taskID: taskID) == .failed
            } onTimeout: {
                Issue.record("flutter analyze did not fail: \(taskManager.taskStatus(taskID: taskID))")
            }
            let source = root.appending(path: "lib/demo_pkg.dart").standardizedFileURL.path
            await waitForExpectation(timeout: .seconds(5)) {
                workspace.taskDiagnostics.all.contains { $0.filePath == source }
            } onTimeout: {}
            let problems = workspace.taskDiagnostics.all
            let terminal = taskManager.activeTasks[taskID]?.output?.getBufferAsString() ?? ""
            #expect(problems.contains { $0.severity == .error && $0.filePath == source && $0.line == 1 },
                    "Parsed: \(problems.map(\.summary)) Terminal: \(terminal)")
        }
    }
}

// MARK: - A real workspace

extension HybridWorkspaceDocumentTests {
    /// Opens a real hybrid project read-only (set `TEST_RUNNER_HYBRID_WORKSPACE` to its folder) and
    /// prints what CodeEdit finds and generates there.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["HYBRID_WORKSPACE"] != nil))
    func describesARealWorkspace() async throws {
        let root = URL(filePath: try #require(ProcessInfo.processInfo.environment["HYBRID_WORKSPACE"]))
        let workspace = try open(root)
        defer { workspace.close() }
        await waitForExpectation(timeout: .seconds(30)) {
            !(workspace.taskManager?.generatedTasks.isEmpty ?? true)
                && workspace.projectInventory?.toolchainStatus != nil
        } onTimeout: {
            Issue.record("Discovery did not finish")
        }
        let inventory = try #require(workspace.projectInventory?.inventory)
        var report = ["Toolchains: \(inventory.toolchains.map(\.title))"]
        report += inventory.components.map { component in
            let role = component.role.title
            return "Component: \(component.kind.title) \(component.name) at \(component.relativePath) [\(role)]"
        }
        report += inventory.links.map { "Link: \($0.source) \($0.summary) \($0.target) via \($0.evidence)" }
        report += inventory.configurationFiles.map { "File: \($0.toolchain.title) \($0.relativePath)" }
        report += (workspace.taskManager?.generatedTasks ?? []).map { task in
            "Task: \(task.name) | cwd=\(task.workingDirectory.isEmpty ? "." : task.workingDirectory) | \(task.command)"
        }
        if let status = workspace.projectInventory?.toolchainStatus {
            report.append("CMake: \(status.cmakeVersion ?? "-")")
            for (path, rust) in status.rust {
                report.append("Rust \(path): \(rust.activeToolchain ?? "-") problem=\(rust.problem ?? "none")")
            }
        }
        print(report.map { "HYBRID-REPORT \($0)" }.joined(separator: "\n"))
        #expect(inventory.isHybrid)
    }
}

private extension URL {
    /// The URL, after creating its parent folder.
    func creatingParentFolder() throws -> URL {
        try FileManager.default.createDirectory(at: deletingLastPathComponent(), withIntermediateDirectories: true)
        return self
    }
}
