//
//  CMakeToolchainAndTargetTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 9/30/26.
//

import XCTest
@testable import CodeEdit

/// Toolchain output parsing, argument splitting, executable target discovery, and launch
/// configuration for the project editor's CMake settings.
final class CMakeToolchainAndTargetTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CMakeToolchainAndTargetTests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
    }

    // MARK: - Parsing

    func testCompilerVersionParsing() {
        let apple = CMakeToolchainDetector.parseCompilerVersion(
            "Apple clang version 17.0.0 (clang-1700.0.13.3)\nTarget: arm64-apple-darwin25.0.0",
            path: "/usr/bin/clang"
        )
        XCTAssertEqual(apple.family, .appleClang)
        XCTAssertEqual(apple.title, "Apple Clang 17.0.0")

        let homebrew = CMakeToolchainDetector.parseCompilerVersion(
            "Homebrew clang version 19.1.7\nTarget: arm64-apple-darwin24.2.0",
            path: "/opt/homebrew/opt/llvm/bin/clang"
        )
        XCTAssertEqual(homebrew.title, "Homebrew Clang 19.1.7")

        let llvm = CMakeToolchainDetector.parseCompilerVersion("clang version 18.1.8 (https://llvm.org)", path: "c")
        XCTAssertEqual(llvm.title, "Clang 18.1.8")

        let gcc = CMakeToolchainDetector.parseCompilerVersion(
            "g++-14 (Homebrew GCC 14.2.0_1) 14.2.0\nCopyright (C) 2024 Free Software Foundation, Inc.",
            path: "/opt/homebrew/bin/g++-14"
        )
        XCTAssertEqual(gcc.family, .gcc)
        XCTAssertEqual(gcc.title, "Homebrew GCC 14.2.0")

        XCTAssertEqual(CMakeToolchainDetector.parseCMakeVersion("cmake version 3.31.2\n\nCMake suite"), "3.31.2")
        XCTAssertNil(CMakeToolchainDetector.parseCMakeVersion("command not found"))
    }

    func testSearchDirectoriesPutPathFirstWithoutDuplicates() {
        let directories = CMakeToolchainDetector.searchDirectories(path: "/opt/homebrew/bin:relative:/custom/bin/")
        XCTAssertEqual(directories.first, "/opt/homebrew/bin")
        XCTAssertEqual(directories.filter { $0 == "/opt/homebrew/bin" }.count, 1)
        XCTAssertFalse(directories.contains("relative"))
        XCTAssertTrue(directories.contains("/usr/bin"))
    }

    func testCommandLineArgumentSplitting() {
        XCTAssertEqual(CommandLineArguments.split(""), [])
        XCTAssertEqual(CommandLineArguments.split("  -v   --level 3 "), ["-v", "--level", "3"])
        XCTAssertEqual(
            CommandLineArguments.split(#"--name "Jane Doe" 'it''s' a\ b"#),
            ["--name", "Jane Doe", "its", "a b"]
        )
        XCTAssertEqual(CommandLineArguments.split(#""say \"hi\"" "" '$HOME'"#), [#"say "hi""#, "", "$HOME"])
        XCTAssertEqual(CommandLineArguments.split(#""unterminated value"#), ["unterminated value"])
    }

    // MARK: - Executable targets

    func testDeclaredExecutablesSkipImportedAndAliasTargets() throws {
        let listFile = """
        add_executable(app main.cpp)
          ADD_EXECUTABLE (tool-cli
              tool.cpp)
        add_executable(external IMPORTED)
        add_executable(app_alias ALIAS app)
        # add_executable(commented main.cpp)
        add_executable(${NAME} main.cpp)
        """
        XCTAssertEqual(CMakeExecutableTargets.executableNames(in: listFile), ["app", "tool-cli"])

        try listFile.write(to: root.appending(path: "CMakeLists.txt"), atomically: true, encoding: .utf8)
        let nested = root.appending(path: "tools/extra")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "add_executable(extra x.c)"
            .write(to: nested.appending(path: "CMakeLists.txt"), atomically: true, encoding: .utf8)
        let buildTree = root.appending(path: "build")
        try FileManager.default.createDirectory(at: buildTree, withIntermediateDirectories: true)
        try "add_executable(generated x.c)"
            .write(to: buildTree.appending(path: "CMakeLists.txt"), atomically: true, encoding: .utf8)

        XCTAssertEqual(CMakeExecutableTargets.declaredExecutables(sourceDirectory: root), ["app", "extra", "tool-cli"])
    }

    func testFileAPIReplyProvidesArtifactsForChosenConfiguration() throws {
        let buildDirectory = root.appending(path: "build")
        let reply = buildDirectory.appending(path: ".cmake/api/v1/reply")
        try FileManager.default.createDirectory(at: reply, withIntermediateDirectories: true)
        let files: [String: String] = [
            "index-2026-09-30T00-00-00-0000.json":
                #"{"objects": [{"kind": "codemodel", "version": {"major": 2}, "jsonFile": "codemodel.json"}]}"#,
            "codemodel.json": #"""
            {"configurations": [
              {"name": "Debug", "targets": [{"name": "app", "jsonFile": "app-debug.json"},
                                            {"name": "core", "jsonFile": "core.json"}]},
              {"name": "Release", "targets": [{"name": "app", "jsonFile": "app-release.json"}]}
            ]}
            """#,
            "app-debug.json": #"{"name": "app", "type": "EXECUTABLE", "artifacts": [{"path": "Debug/app"}]}"#,
            "app-release.json": #"{"name": "app", "type": "EXECUTABLE", "artifacts": [{"path": "Release/app"}]}"#,
            "core.json": #"{"name": "core", "type": "STATIC_LIBRARY", "artifacts": [{"path": "libcore.a"}]}"#
        ]
        for (name, contents) in files {
            try contents.write(to: reply.appending(path: name), atomically: true, encoding: .utf8)
        }

        let release = CMakeExecutableTargets.load(
            sourceDirectory: root,
            buildDirectory: buildDirectory,
            configuration: "Release"
        )
        let releaseBinary = buildDirectory.appending(path: "Release/app")
        XCTAssertEqual(release, [CMakeExecutableTarget(name: "app", artifact: releaseBinary)])
        let fallback = CMakeExecutableTargets.load(
            sourceDirectory: root,
            buildDirectory: buildDirectory,
            configuration: nil
        )
        XCTAssertEqual(fallback.map(\.artifact?.lastPathComponent), ["app"])
        XCTAssertEqual(fallback.first?.artifact?.deletingLastPathComponent().lastPathComponent, "Debug")

        CMakeExecutableTargets.writeQuery(buildDirectory: buildDirectory)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: buildDirectory.appending(path: ".cmake/api/v1/query/codemodel-v2").path
        ))
    }

    // MARK: - Launch configuration

    func testLaunchConfigurationResolvesTargetsPathsAndEnvironment() {
        let targets = [CMakeExecutableTarget(name: "app", artifact: root.appending(path: "build/app"))]
        var run = CMakeProjectSettings.Run(
            targetName: "app",
            workingDirectory: "data",
            arguments: "--port 80 \"a b\"",
            environment: [.init(name: "LOG", value: "1"), .init(name: "OFF", value: "0", isEnabled: false)]
        )

        let launch = run.launchConfiguration(sourceDirectory: root, targets: targets)
        XCTAssertEqual(launch?.executable, root.appending(path: "build/app"))
        XCTAssertEqual(launch?.arguments, ["--port", "80", "a b"])
        XCTAssertEqual(launch?.workingDirectory, root.appending(path: "data"))
        XCTAssertEqual(launch?.environment, ["LOG": "1"])

        run.targetName = "missing"
        XCTAssertNil(run.launchConfiguration(sourceDirectory: root, targets: targets))

        run.customExecutable = ""
        XCTAssertFalse(run.hasExecutable, "An empty custom path is not a target")
        run.customExecutable = "/usr/bin/true"
        XCTAssertEqual(run.launchConfiguration(sourceDirectory: root, targets: [])?.executable.path, "/usr/bin/true")
        run.workingDirectory = nil
        XCTAssertEqual(run.launchConfiguration(sourceDirectory: root, targets: [])?.workingDirectory, root)
    }
}
