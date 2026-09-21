//
//  CMakeBuildControllerTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 9/14/26.
//

import XCTest
@testable import CodeEdit

@MainActor
final class CMakeBuildControllerTests: XCTestCase {
    private var root: URL!

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
    }

    /// Builds run through a fake `cmake` shell script so tests need no CMake installation.
    /// The script records its arguments, prints canned compiler output for `--build`, and
    /// optionally sleeps to exercise cancellation.
    private func makeFakeCMake(
        recordArgumentsTo record: URL,
        buildOutput: String = "",
        exitCode: Int = 0,
        sleepDuration: Int = 0
    ) throws -> URL {
        let script = """
        #!/bin/bash
        echo "$@" >> "\(record.path)"
        if [[ "$*" == *"--build"* ]]; then
        \(sleepDuration > 0 ? "  sleep \(sleepDuration)" : "")  cat <<'BUILD_OUTPUT'
        \(buildOutput)
        BUILD_OUTPUT
          exit \(exitCode)
        fi
        exit 0
        """
        let url = root.appending(path: "fake-cmake.sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func makeProject(presets: String? = nil) throws -> URL {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "cmake_minimum_required(VERSION 3.21)\nproject(Example LANGUAGES CXX)"
            .write(to: root.appending(path: "CMakeLists.txt"), atomically: true, encoding: .utf8)
        if let presets {
            try presets.write(to: root.appending(path: "CMakePresets.json"), atomically: true, encoding: .utf8)
        }
        return root
    }

    private func makeController(presets: String? = nil) async throws -> CMakeBuildController {
        let root = try makeProject(presets: presets)
        let workspace = CMakeWorkspace(sourceDirectory: root, defaults: userDefaults())
        workspace.reload()
        await workspace.waitForReload()
        return CMakeBuildController(sourceDirectory: root, workspace: workspace)
    }

    private func userDefaults() -> UserDefaults {
        let suite = "CMakeBuildTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func awaitBuild(_ controller: CMakeBuildController) async {
        let finished = expectation(description: "build finished")
        controller.onBuildFinished = { _ in finished.fulfill() }
        // Yield once so a completion that became ready before the handler was set still fires.
        await Task.yield()
        await fulfillment(of: [finished], timeout: 15, enforceOrder: false)
    }

    // MARK: - Tests

    func testBuildWithoutPresetsRunsConfigureThenBuildAndCollectsDiagnostics() async throws {
        let controller = try await makeController()
        let record = root.appending(path: "arguments.txt")
        let fake = try makeFakeCMake(
            recordArgumentsTo: record,
            buildOutput: """
            [1/1] Linking CXX executable example
            /tmp/example/main.cpp:4:9: warning: unused variable 'value' [-Wunused-variable]
            /tmp/example/main.cpp:5:5: error: use of undeclared identifier 'missing'
            clang: error: linker command failed with exit code 1 (use -v to see invocation)
            """,
            exitCode: 1
        )

        controller.start(cmake: fake.path)
        await awaitBuild(controller)

        XCTAssertEqual(controller.outcome, .failed(exitCode: 1))
        XCTAssertFalse(controller.isBuilding)
        XCTAssertEqual(controller.diagnostics.count, 3)
        XCTAssertEqual(controller.errorCount, 2)
        XCTAssertEqual(controller.warningCount, 1)
        let error = try XCTUnwrap(controller.diagnostics.first { $0.severity == .error && $0.filePath != nil })
        XCTAssertEqual(error.filePath, "/tmp/example/main.cpp")
        XCTAssertEqual(error.line, 5)
        XCTAssertEqual(error.column, 5)

        let arguments = try String(contentsOf: record, encoding: .utf8)
        XCTAssertTrue(arguments.contains("--build"), arguments)
        XCTAssertTrue(arguments.contains(root.appending(path: "build").path), arguments)
    }

    func testBuildUsesSelectedBuildPreset() async throws {
        let presets = #"""
        {"version": 3, "configurePresets": [
          {"name": "debug", "generator": "Ninja", "binaryDir": "${sourceDir}/out/debug",
           "cacheVariables": {"CMAKE_BUILD_TYPE": "Debug"}}
        ], "buildPresets": [
          {"name": "debug-build", "configurePreset": "debug"}
        ]}
        """#
        let controller = try await makeController(presets: presets)
        let record = root.appending(path: "arguments.txt")
        let fake = try makeFakeCMake(recordArgumentsTo: record, exitCode: 0)
        // Point the preset's binary directory at a cache so the configure step is skipped.
        let binaryDir = root.appending(path: "out/debug")
        try writeCache(home: root, cacheDirectory: binaryDir, in: binaryDir)

        controller.start(cmake: fake.path)
        await awaitBuild(controller)

        XCTAssertEqual(controller.outcome, .success)
        XCTAssertEqual(controller.diagnostics.count, 0)
        let arguments = try String(contentsOf: record, encoding: .utf8)
        XCTAssertTrue(arguments.contains("--preset debug-build"), arguments)
    }

    func testStoppingABuildReportsCancellation() async throws {
        let controller = try await makeController()
        let record = root.appending(path: "arguments.txt")
        let fake = try makeFakeCMake(recordArgumentsTo: record, buildOutput: "", exitCode: 0, sleepDuration: 30)

        controller.start(cmake: fake.path)
        XCTAssertTrue(controller.isBuilding)
        controller.stop()
        await awaitBuild(controller)

        XCTAssertEqual(controller.outcome, .cancelled)
        XCTAssertFalse(controller.isBuilding)
    }

    func testBuildReconfiguresWhenCacheBelongsToAnotherProject() async throws {
        let controller = try await makeController()
        let buildDirectory = root.appending(path: "build")
        try writeCache(
            home: URL(filePath: "/Users/other/Supersonic Transport/panair"),
            cacheDirectory: URL(filePath: "/Users/other/Supersonic Transport/panair/build"),
            in: buildDirectory
        )
        let staleFiles = buildDirectory.appending(path: "CMakeFiles")
        try FileManager.default.createDirectory(at: staleFiles, withIntermediateDirectories: true)
        try "stale".write(to: staleFiles.appending(path: "VerifyGlobs.cmake"), atomically: true, encoding: .utf8)
        try "keep".write(to: buildDirectory.appending(path: "libkeep.a"), atomically: true, encoding: .utf8)

        let record = root.appending(path: "arguments.txt")
        let fake = try makeFakeCMake(recordArgumentsTo: record, exitCode: 0)
        controller.start(cmake: fake.path)
        await awaitBuild(controller)

        XCTAssertEqual(controller.outcome, .success)
        let arguments = try String(contentsOf: record, encoding: .utf8)
        XCTAssertTrue(arguments.contains("-S"), arguments)
        XCTAssertTrue(arguments.contains("--build"), arguments)
        XCTAssertFalse(FileManager.default.fileExists(atPath: buildDirectory.appending(path: "CMakeCache.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleFiles.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: buildDirectory.appending(path: "libkeep.a").path))
    }

    func testBuildReconfiguresWhenCacheFileDirectoryDiffers() async throws {
        let controller = try await makeController()
        let buildDirectory = root.appending(path: "build")
        try writeCache(
            home: root,
            cacheDirectory: URL(filePath: "/tmp/other-build"),
            in: buildDirectory
        )

        let record = root.appending(path: "arguments.txt")
        let fake = try makeFakeCMake(recordArgumentsTo: record, exitCode: 0)
        controller.start(cmake: fake.path)
        await awaitBuild(controller)

        XCTAssertEqual(controller.outcome, .success)
        let arguments = try String(contentsOf: record, encoding: .utf8)
        XCTAssertTrue(arguments.contains("-S"), arguments)
        XCTAssertTrue(arguments.contains("--build"), arguments)
    }

    func testBuildReconfiguresWhenCacheIsMalformed() async throws {
        let controller = try await makeController()
        let buildDirectory = root.appending(path: "build")
        try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)
        try "not a cmake cache".write(
            to: buildDirectory.appending(path: "CMakeCache.txt"),
            atomically: true,
            encoding: .utf8
        )

        let record = root.appending(path: "arguments.txt")
        let fake = try makeFakeCMake(recordArgumentsTo: record, exitCode: 0)
        controller.start(cmake: fake.path)
        await awaitBuild(controller)

        XCTAssertEqual(controller.outcome, .success)
        let arguments = try String(contentsOf: record, encoding: .utf8)
        XCTAssertTrue(arguments.contains("-S"), arguments)
        XCTAssertTrue(arguments.contains("--build"), arguments)
    }

    private func writeCache(home: URL, cacheDirectory: URL, in buildDirectory: URL) throws {
        try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)
        let contents = """
        # This is the CMakeCache file.
        CMAKE_HOME_DIRECTORY:INTERNAL=\(home.path)
        CMAKE_CACHEFILE_DIR:INTERNAL=\(cacheDirectory.path)
        """
        try contents.write(
            to: buildDirectory.appending(path: "CMakeCache.txt"),
            atomically: true,
            encoding: .utf8
        )
    }
}
