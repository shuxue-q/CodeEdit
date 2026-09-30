//
//  CMakeProjectSettingsStoreTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 9/30/26.
//

import XCTest
@testable import CodeEdit

@MainActor
final class CMakeProjectSettingsStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CMakeProjectSettingsStoreTests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "cmake_minimum_required(VERSION 3.21)\nproject(Example LANGUAGES CXX)\nadd_executable(example main.cpp)"
            .write(to: root.appending(path: "CMakeLists.txt"), atomically: true, encoding: .utf8)
    }

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
    }

    func testOpeningDoesNotCreateFilesAndSavingWritesSortedJSON() throws {
        let store = CMakeProjectSettingsStore(sourceDirectory: root, workspace: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: ".codeedit").path))

        store.settings.toolchain.generator = "Ninja"
        store.settings.variables = [.init(name: "BUILD_TESTING", value: "ON")]
        store.flush()

        let file = root.appending(path: ".codeedit/cmake-settings.json")
        let contents = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(contents.contains(#""generator" : "Ninja""#), contents)
        XCTAssertLessThan(
            try XCTUnwrap(contents.range(of: "\"build\"")).lowerBound,
            try XCTUnwrap(contents.range(of: "\"toolchain\"")).lowerBound,
            "Keys are sorted"
        )

        let reloaded = CMakeProjectSettingsStore(sourceDirectory: root, workspace: nil)
        XCTAssertEqual(reloaded.settings.toolchain.generator, "Ninja")
        XCTAssertEqual(reloaded.settings.variables.map(\.name), ["BUILD_TESTING"])
        XCTAssertEqual(CMakeProjectSettingsStore.savedSettings(sourceDirectory: root)?.toolchain.generator, "Ninja")
    }

    func testUnreadableFileIsReportedAndKeptUntilEdited() throws {
        let file = root.appending(path: ".codeedit/cmake-settings.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{ not json".write(to: file, atomically: true, encoding: .utf8)

        let store = CMakeProjectSettingsStore(sourceDirectory: root, workspace: nil)
        XCTAssertNotNil(store.loadError)
        XCTAssertEqual(store.settings, CMakeProjectSettings())
        store.flush()
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "{ not json")
    }

    func testEditsAreSavedAfterAShortDelay() async throws {
        let store = CMakeProjectSettingsStore(sourceDirectory: root, workspace: nil)
        store.settings.build.cxxStandard = .cxx23
        let file = root.appending(path: ".codeedit/cmake-settings.json")
        for _ in 0..<40 where !FileManager.default.fileExists(atPath: file.path) {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(CMakeProjectSettingsStore.savedSettings(sourceDirectory: root)?.build.cxxStandard, .cxx23)
    }

    func testResolvesLaunchConfigurationFromDeclaredTargetsAndCustomPath() async {
        let store = CMakeProjectSettingsStore(sourceDirectory: root, workspace: nil)
        let unset = await store.resolveLaunchConfiguration()
        XCTAssertNil(unset)

        store.settings.run.targetName = "example"
        let unbuilt = await store.resolveLaunchConfiguration()
        XCTAssertNil(unbuilt, "Before a configure the target's binary location is unknown")
        XCTAssertEqual(store.executableTargets.map(\.name), ["example"])

        store.settings.run.customExecutable = "bin/tool"
        store.settings.run.arguments = "-x 1"
        let custom = await store.resolveLaunchConfiguration()
        XCTAssertEqual(custom?.executable, root.appending(path: "bin/tool"))
        XCTAssertEqual(custom?.arguments, ["-x", "1"])
        store.close()
    }

    // MARK: - Build integration

    /// A fake `cmake` that records its arguments and, when configuring, writes a cache for the
    /// requested build directory the way CMake would.
    private func makeFakeCMake(recordingTo record: URL) throws -> URL {
        let script = """
        #!/bin/bash
        echo "$@" >> "\(record.path)"
        if [[ "$1" == "-S" ]]; then
          mkdir -p "$4/CMakeFiles"
          printf 'CMAKE_HOME_DIRECTORY:INTERNAL=%s\\nCMAKE_CACHEFILE_DIR:INTERNAL=%s\\n' "$2" "$4" > "$4/CMakeCache.txt"
        fi
        exit 0
        """
        let url = root.appending(path: "fake-cmake.sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func testBuildConfiguresOnceAndAgainAfterSettingsChange() async throws {
        let suite = "CMakeProjectSettingsStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let workspace = CMakeWorkspace(sourceDirectory: root, defaults: defaults)
        workspace.reload()
        await workspace.waitForReload()
        let store = CMakeProjectSettingsStore(sourceDirectory: root, workspace: workspace)
        store.settings.build.buildDirectory = "out"
        store.settings.variables = [.init(name: "BUILD_TESTING", value: "ON")]
        let controller = CMakeBuildController(sourceDirectory: root, workspace: workspace, projectSettings: store)
        let record = root.appending(path: "arguments.txt")
        let fake = try makeFakeCMake(recordingTo: record)

        func build() async throws -> [String] {
            try? FileManager.default.removeItem(at: record)
            let finished = expectation(description: "build finished")
            controller.onBuildFinished = { _ in finished.fulfill() }
            controller.start(cmake: fake.path)
            await fulfillment(of: [finished], timeout: 15)
            XCTAssertEqual(controller.outcome, .success)
            return try String(contentsOf: record, encoding: .utf8).split(separator: "\n").map(String.init)
        }

        let first = try await build()
        XCTAssertEqual(first.count, 2, "Configure, then build")
        XCTAssertTrue(first[0].contains("-B \(root.appending(path: "out").path)"), first[0])
        XCTAssertTrue(first[0].contains("-DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON"), first[0])
        XCTAssertEqual(first[1], "--build \(root.appending(path: "out").path)")

        let second = try await build()
        XCTAssertEqual(second.count, 1, "The recorded arguments still match, so only the build runs")

        store.settings.build.configuration = .release
        let third = try await build()
        XCTAssertEqual(third.count, 2)
        XCTAssertTrue(third[0].contains("-DCMAKE_BUILD_TYPE=Release"), third[0])
        store.close()
    }
}
