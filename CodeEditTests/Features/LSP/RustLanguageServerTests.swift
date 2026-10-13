//
//  RustLanguageServerTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation
import Testing
import LanguageServerProtocol
@testable import CodeEdit

/// Locating rust-analyzer and the settings it is started with.
@Suite
struct RustLanguageServerTests {
    /// Writes an executable shell script at `url`, creating its parent directories.
    private func makeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// A fake tool runner answering each `(tool, first argument)` pair with a status and output.
    private func runner(_ answers: [String: (Int32, String)]) -> LanguageServerDetector.ToolRunner {
        return { path, arguments in
            let name = URL(fileURLWithPath: path).lastPathComponent
            return answers["\(name) \(arguments.first ?? "")"].map { (status: $0.0, output: $0.1) }
        }
    }

    // MARK: - Detection

    @Test
    func rustAnalyzerIsSupportedWithAnInstallHint() throws {
        let server = try #require(LanguageServerDetector.supportedServers.first { $0.executable == "rust-analyzer" })
        #expect(server.languageIds == ["rust"])
        #expect(server.arguments.isEmpty)
        #expect(server.installHint == "rustup component add rust-analyzer")
        #expect(LanguageServerDetector.supportedLanguageIds.contains("rust"))
        let clangd = try #require(LanguageServerDetector.supportedServers.first { $0.executable == "clangd" })
        #expect(clangd.installHint == nil)
    }

    @Test
    func rustupComponentBinaryIsPreferredOverTheProxy() throws {
        try withTempDir { root in
            let component = root.appending(path: "toolchains/stable/bin/rust-analyzer")
            try makeExecutable(at: component)
            let resolved = LanguageServerDetector.resolveRustAnalyzerExecutable(
                rustAnalyzerPath: "/home/.cargo/bin/rust-analyzer",
                rustupPath: "/home/.cargo/bin/rustup",
                run: runner(["rustup which": (0, component.path + "\n"), "rust-analyzer --version": (0, "1.0")])
            )
            #expect(resolved == component.path)
        }
    }

    @Test
    func missingComponentIsNotFound() {
        // The proxy exists, but neither `rustup which` nor the proxy itself finds the component.
        let resolved = LanguageServerDetector.resolveRustAnalyzerExecutable(
            rustAnalyzerPath: "/home/.cargo/bin/rust-analyzer",
            rustupPath: "/home/.cargo/bin/rustup",
            run: runner([
                "rustup which": (1, ""),
                "rust-analyzer --version": (1, "error: Unknown binary 'rust-analyzer'")
            ])
        )
        #expect(resolved == nil)
    }

    @Test
    func standaloneBinaryIsUsedWhenItRuns() {
        let resolved = LanguageServerDetector.resolveRustAnalyzerExecutable(
            rustAnalyzerPath: "/opt/homebrew/bin/rust-analyzer",
            rustupPath: nil,
            run: runner(["rust-analyzer --version": (0, "rust-analyzer 1.97.1")])
        )
        #expect(resolved == "/opt/homebrew/bin/rust-analyzer")
    }

    @Test
    func standaloneBinaryIsUsedWhenRustupHasNoComponent() {
        let resolved = LanguageServerDetector.resolveRustAnalyzerExecutable(
            rustAnalyzerPath: "/opt/homebrew/bin/rust-analyzer",
            rustupPath: "/home/.cargo/bin/rustup",
            run: runner(["rustup which": (1, ""), "rust-analyzer --version": (0, "rust-analyzer 1.97.1")])
        )
        #expect(resolved == "/opt/homebrew/bin/rust-analyzer")
    }

    @Test
    func rustupAnswerThatIsNotAnExecutableFallsBack() {
        let resolved = LanguageServerDetector.resolveRustAnalyzerExecutable(
            rustAnalyzerPath: nil,
            rustupPath: "/home/.cargo/bin/rustup",
            run: runner(["rustup which": (0, "/nonexistent/rust-analyzer\n")])
        )
        #expect(resolved == nil)
    }

    @Test
    func executablePathRoutesRustAnalyzerThroughTheCheck() throws {
        let server = try #require(LanguageServerDetector.supportedServers.first { $0.executable == "rust-analyzer" })
        let located = ["rust-analyzer": "/home/.cargo/bin/rust-analyzer"]
        let failing = runner(["rust-analyzer --version": (1, "")])
        #expect(LanguageServerDetector.executablePath(for: server, located: located, run: failing) == nil)
        let working = runner(["rust-analyzer --version": (0, "")])
        let found = LanguageServerDetector.executablePath(for: server, located: located, run: working)
        #expect(found == located["rust-analyzer"])
    }

    @Test
    func runToolReportsStatusAndOutput() throws {
        let result = try #require(LanguageServerDetector.runTool("/bin/echo", arguments: ["hello"], environment: [:]))
        #expect(result.status == 0)
        #expect(result.output == "hello\n")
        let failure = try #require(LanguageServerDetector.runTool("/usr/bin/false", arguments: [], environment: [:]))
        #expect(failure.status != 0)
        #expect(LanguageServerDetector.runTool("/nonexistent/tool", arguments: [], environment: [:]) == nil)
    }

    // MARK: - Initialization options

    private static let baseOptions: [String: LSPAny] = [
        "checkOnSave": .bool(true),
        "check": .hash(["command": .string("check")]),
        "completion": .hash(["callable": .hash(["snippets": .string("fill_arguments")])]),
        "files": .hash(["watcher": .string("server")])
    ]

    @Test
    func rustOptionsWithoutLinkedProjects() {
        #expect(LanguageServerConfiguration.initializationOptions(for: "rust") == .hash(Self.baseOptions))
    }

    @Test
    func nestedCargoWorkspaceBecomesALinkedProject() throws {
        try withTempDir { root in
            let manifest = root.appending(path: "rust/Cargo.toml")
            try FileManager.default.createDirectory(
                at: manifest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "[workspace]\nmembers = []\n".write(to: manifest, atomically: true, encoding: .utf8)

            let options = LanguageServerConfiguration.initializationOptions(for: "rust", workspacePath: root.path)
            guard case .hash(let values) = options, case .array(let linked) = values["linkedProjects"] else {
                Issue.record("No linkedProjects in \(options)")
                return
            }
            #expect(linked.count == 1)
            if case .string(let path) = linked.first {
                #expect(URL(fileURLWithPath: path).resolvingSymlinksInPath() == manifest.resolvingSymlinksInPath())
            }
        }
    }

    @Test
    func rootCargoProjectGetsTheBaseOptions() throws {
        try withTempDir { root in
            let manifest = root.appending(path: "Cargo.toml")
            try "[package]\nname = \"a\"\n".write(to: manifest, atomically: true, encoding: .utf8)
            let options = LanguageServerConfiguration.initializationOptions(for: "rust", workspacePath: root.path)
            #expect(options == .hash(Self.baseOptions))
        }
    }

    @Test(arguments: ["c", "cpp", "objective-c", "cmake", "dart"])
    func otherLanguagesIgnoreTheWorkspace(languageId: String) {
        #expect(
            LanguageServerConfiguration.initializationOptions(for: languageId, workspacePath: "/tmp")
                == LanguageServerConfiguration.initializationOptions(for: languageId)
        )
    }

    @Test
    func initializeParamsCarryTheGivenOptions() async throws {
        let options: LSPAny = .hash(["linkedProjects": .array([.string("/tmp/rust/Cargo.toml")])])
        let params = try await LanguageServer<CodeFileDocument>.getInitParams(
            languageId: "rust",
            workspacePath: "/tmp/project",
            initializationOptions: options
        )()
        #expect(params.initializationOptions == options)
        let defaults = try await LanguageServer<CodeFileDocument>.getInitParams(
            languageId: "rust",
            workspacePath: "/tmp/project"
        )()
        #expect(defaults.initializationOptions == .hash(Self.baseOptions))
    }

    // MARK: - Workspace configuration

    @Test
    func rustAnalyzerSectionIsAnsweredWithTheStartOptions() {
        let started: LSPAny = .hash(["linkedProjects": .array([.string("/w/rust/Cargo.toml")])])
        let params = ConfigurationParams(items: [
            ConfigurationItem(scopeUri: nil, section: "rust-analyzer"),
            ConfigurationItem(scopeUri: nil, section: "editor")
        ])
        let values = LanguageServerConfiguration.workspaceConfiguration(
            for: params,
            languageId: "rust",
            initializationOptions: started
        )
        #expect(values == [started, .null])
        let withoutStart = LanguageServerConfiguration.workspaceConfiguration(for: params, languageId: "rust")
        #expect(withoutStart == [.hash(Self.baseOptions), .null])
    }

    @Test
    func otherServersDoNotGetRustSettings() {
        let params = ConfigurationParams(items: [ConfigurationItem(scopeUri: nil, section: "rust-analyzer")])
        #expect(LanguageServerConfiguration.workspaceConfiguration(for: params, languageId: "cpp") == [.null])
    }

    @Test
    func onlyRustGetsProgressRepliesAndSaveNotifications() {
        #expect(LanguageServerConfiguration.workDoneProgressLanguageIds == ["rust"])
        #expect(LanguageServerConfiguration.didSaveLanguageIds == ["rust"])
    }
}
