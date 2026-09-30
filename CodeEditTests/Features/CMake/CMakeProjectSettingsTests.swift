//
//  CMakeProjectSettingsTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 9/30/26.
//

import XCTest
@testable import CodeEdit

final class CMakeProjectSettingsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CMakeProjectSettingsTests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
    }

    // MARK: - Model

    func testDecodingFallsBackPerKeyInsteadOfFailing() throws {
        let json = #"""
        {
          "toolchain": {"cCompiler": "/usr/bin/clang", "cxxCompiler": 42, "generator": "  "},
          "build": {"configuration": "Fastest", "buildDirectory": "out", "cxxStandard": "20"},
          "variables": [{"name": "BUILD_TESTING", "value": "ON"}, {"name": "OFF_ONE", "value": "1", "enabled": false}],
          "run": "not an object"
        }
        """#
        let settings = try JSONDecoder().decode(CMakeProjectSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.toolchain.cCompiler, "/usr/bin/clang")
        XCTAssertNil(settings.toolchain.cxxCompiler)
        XCTAssertNil(settings.toolchain.generator, "Blank strings mean the default")
        XCTAssertEqual(settings.build.configuration, .debug)
        XCTAssertEqual(settings.build.buildDirectory, "out")
        XCTAssertEqual(settings.build.cxxStandard, .cxx20)
        XCTAssertEqual(settings.variables.map(\.name), ["BUILD_TESTING", "OFF_ONE"])
        XCTAssertEqual(settings.variables.map(\.isEnabled), [true, false])
        XCTAssertEqual(settings.run, CMakeProjectSettings.Run())
    }

    func testEncodingRoundTripsWithoutRowIdentifiers() throws {
        var settings = CMakeProjectSettings()
        settings.toolchain.generator = "Ninja"
        settings.build.cxxStandard = .cxx23
        settings.variables = [.init(name: "A", value: "1")]
        settings.run.environment = [.init(name: "LOG", value: "debug", isEnabled: false)]

        let data = try JSONEncoder().encode(settings)
        XCTAssertFalse(try XCTUnwrap(String(bytes: data, encoding: .utf8)).contains("\"id\""))
        var decoded = try JSONDecoder().decode(CMakeProjectSettings.self, from: data)
        decoded.variables = decoded.variables.enumerated().map { index, row in
            var row = row
            row.id = settings.variables[index].id
            return row
        }
        decoded.run.environment[0].id = settings.run.environment[0].id
        XCTAssertEqual(decoded, settings)
    }

    // MARK: - Configure arguments

    func testWithoutSettingsArgumentsMatchPreviousBehavior() {
        let options = makeOptions(settings: nil)
        let build = root.appending(path: "build").path
        XCTAssertEqual(options.configureArguments, ["-S", root.path, "-B", build, "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"])
        XCTAssertEqual(options.buildArguments, ["--build", build])
    }

    func testSettingsProduceToolchainAndVariableDefinitions() {
        var settings = CMakeProjectSettings()
        settings.toolchain = .init(cCompiler: "/opt/homebrew/bin/gcc-14", cxxCompiler: "", generator: "Ninja")
        settings.build = .init(configuration: .relWithDebInfo, buildDirectory: "out/rel", cxxStandard: .cxx20)
        settings.variables = [
            .init(name: "BUILD_TESTING", value: "ON"),
            .init(name: "-DUSE_FOO:BOOL", value: "OFF"),
            .init(name: "DISABLED", value: "1", isEnabled: false),
            .init(name: "BAD NAME", value: "1"),
            .init(name: "", value: "empty")
        ]
        let options = makeOptions(settings: settings)
        let build = root.appending(path: "out/rel").path

        XCTAssertEqual(options.buildDirectory.path, build)
        XCTAssertEqual(options.configureArguments, [
            "-S", root.path, "-B", build, "-G", "Ninja",
            "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
            "-DCMAKE_BUILD_TYPE=RelWithDebInfo",
            "-DCMAKE_C_COMPILER=/opt/homebrew/bin/gcc-14",
            "-DCMAKE_CXX_STANDARD=20",
            "-DBUILD_TESTING=ON",
            "-DUSE_FOO:BOOL=OFF"
        ])
        XCTAssertEqual(options.buildArguments, ["--build", build])
    }

    func testMultiConfigGeneratorChoosesConfigurationAtBuildTime() {
        var settings = CMakeProjectSettings()
        settings.toolchain.generator = "Ninja Multi-Config"
        settings.build.configuration = .release
        let options = makeOptions(settings: settings)

        XCTAssertFalse(options.configureArguments.contains { $0.hasPrefix("-DCMAKE_BUILD_TYPE") })
        XCTAssertEqual(options.buildArguments.suffix(2), ["--config", "Release"])
    }

    func testPresetControlsToolchainButVariablesStillApply() {
        var settings = CMakeProjectSettings()
        settings.toolchain = .init(cCompiler: "/usr/bin/gcc", generator: "Unix Makefiles")
        settings.build.buildDirectory = "ignored"
        settings.variables = [.init(name: "EXTRA", value: "yes")]
        let preset = CMakePreset(
            name: "dev", displayName: nil, generator: "Ninja", binaryDirectory: "out/dev", toolchainFile: nil,
            configurePreset: nil, configuration: nil, cacheVariables: [:], environment: [:]
        )
        let options = CMakeConfigureOptions(
            sourceDirectory: root,
            configurePreset: preset,
            buildPreset: nil,
            settings: settings
        )

        XCTAssertEqual(options.buildDirectory.path, root.appending(path: "out/dev").path)
        XCTAssertEqual(
            options.configureArguments,
            ["--preset", "dev", "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON", "-DEXTRA=yes"]
        )
        XCTAssertNil(options.requestedGenerator)
    }

    // MARK: - Configure step

    func testRequiredStepFollowsCacheAndStamp() throws {
        let buildDirectory = root.appending(path: "build")
        let legacy = makeOptions(settings: nil)
        var settings = CMakeProjectSettings()
        let withSettings = makeOptions(settings: settings)
        XCTAssertEqual(withSettings.requiredStep(), .configure, "Nothing configured yet")

        try writeCache(home: URL(filePath: "/elsewhere"), generator: "Ninja", in: buildDirectory)
        XCTAssertEqual(withSettings.requiredStep(), .configureFromScratch, "Cache from another tree")

        try writeCache(home: root, generator: "Unix Makefiles", in: buildDirectory)
        XCTAssertEqual(legacy.requiredStep(), .buildOnly, "Unstamped directories are trusted without settings")
        XCTAssertEqual(withSettings.requiredStep(), .configure, "Settings apply once to unstamped directories")

        withSettings.writeStamp()
        XCTAssertEqual(withSettings.requiredStep(), .buildOnly)

        settings.variables = [.init(name: "NEW", value: "1")]
        let changed = makeOptions(settings: settings)
        XCTAssertEqual(changed.requiredStep(), .configure)

        settings.toolchain.generator = "Ninja"
        let newGenerator = makeOptions(settings: settings)
        XCTAssertEqual(newGenerator.requiredStep(), .configureFromScratch, "CMake cannot switch generators in place")
    }

    // MARK: - Helpers

    private func makeOptions(settings: CMakeProjectSettings?) -> CMakeConfigureOptions {
        CMakeConfigureOptions(sourceDirectory: root, configurePreset: nil, buildPreset: nil, settings: settings)
    }

    private func writeCache(home: URL, generator: String, in buildDirectory: URL) throws {
        try FileManager.default.createDirectory(
            at: buildDirectory.appending(path: "CMakeFiles"),
            withIntermediateDirectories: true
        )
        let contents = """
        CMAKE_HOME_DIRECTORY:INTERNAL=\(home.path)
        CMAKE_CACHEFILE_DIR:INTERNAL=\(buildDirectory.path)
        CMAKE_GENERATOR:INTERNAL=\(generator)
        """
        try contents.write(to: buildDirectory.appending(path: "CMakeCache.txt"), atomically: true, encoding: .utf8)
    }
}
