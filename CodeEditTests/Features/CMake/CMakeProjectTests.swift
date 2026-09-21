//
//  CMakeProjectTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 9/11/26.
//

import XCTest
@testable import CodeEdit

final class CMakeProjectTests: XCTestCase {
    func testOnlyRootListFileIdentifiesProject() throws {
        let root = try makeProject()
        try FileManager.default.removeItem(at: root.appendingPathComponent("CMakeLists.txt"))
        try write("project(Nested)", to: "nested/CMakeLists.txt", at: root)
        XCTAssertNil(CMakeProject.load(at: root))
        XCTAssertFalse(CMakeProject.isCMakeProject(at: root))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("CMakeLists.txt"), withIntermediateDirectories: true
        )
        XCTAssertNil(CMakeProject.load(at: root))
        XCTAssertFalse(CMakeProject.isCMakeProject(at: root))
    }

    func testProjectMetadataIgnoresCommentsStringsAndFunctionBodies() throws {
        let source = #"""
        # project(Commented)
        #[=[ project(BracketComment) ]=]
        message("project(NotAProject)")
        function(example)
          project(FunctionBody)
        endfunction()
        set(PROJECT_NAME "Actual Project")
        PROJECT(${PROJECT_NAME}
          VERSION 1.2.3
          DESCRIPTION "parentheses ) and # stay inside strings"
          LANGUAGES C CXX)
        """#
        let metadata = try CMakeListParser.parse(source)
        XCTAssertEqual(metadata.name, "Actual Project")
        XCTAssertEqual(metadata.version, "1.2.3")
        XCTAssertEqual(metadata.languages, ["C", "CXX"])
    }

    func testQuotedDelimitersBracketArgumentsAndLanguageDefaults() throws {
        XCTAssertEqual(
            try CMakeListParser.parse(#"message(")") project([=[Bracket Project]=] CXX)"#).name,
            "Bracket Project"
        )
        XCTAssertEqual(try CMakeListParser.parse("project(Default VERSION 1.0)").languages, ["C", "CXX"])
        XCTAssertEqual(try CMakeListParser.parse("project(None LANGUAGES NONE)").languages, [])
        XCTAssertNil(try CMakeListParser.parse("project(${COMPUTED_NAME})").name)
        XCTAssertThrowsError(try CMakeListParser.parse("project(Unclosed"))
    }

    func testProjectWithoutPresetsAndInvalidPresetsRemainIdentified() throws {
        let root = try makeProject()
        var project = try XCTUnwrap(CMakeProject.load(at: root))
        XCTAssertEqual(project.name, "Example")
        XCTAssertTrue(project.configurePresets.isEmpty)
        XCTAssertTrue(project.errors.isEmpty)
        try write("{ invalid JSON", to: "CMakePresets.json", at: root)
        project = try XCTUnwrap(CMakeProject.load(at: root))
        XCTAssertEqual(project.name, "Example")
        XCTAssertTrue(project.errors.first?.contains("CMakePresets.json") == true)
    }

    func testConditionalOrUnsetVariablesDoNotReportStaleProjectNames() throws {
        let source = "set(NAME Old)\nif(OPTION)\nset(NAME Computed)\nendif()\nproject(${NAME})"
        XCTAssertNil(try CMakeListParser.parse(source).name)
        XCTAssertNil(try CMakeListParser.parse("set(NAME Old)\nunset(NAME)\nproject(${NAME})").name)
    }

    func testInheritanceCompilerBuildTypeAndChildMacroContext() throws {
        let root = try makeProject(presets: Self.selectionPresets)
        let project = try XCTUnwrap(CMakeProject.load(at: root, environment: [:]))
        XCTAssertTrue(project.errors.isEmpty, project.errors.joined())
        XCTAssertEqual(project.configurePresets.map(\.name), ["debug", "release", "multi"])
        let debug = try XCTUnwrap(project.configurePresets.first)
        XCTAssertEqual(debug.cCompiler, "/usr/bin/clang")
        XCTAssertEqual(debug.cxxCompiler, "/usr/bin/clang++")
        XCTAssertEqual(debug.buildType, "Debug")
        XCTAssertEqual(debug.binaryDirectory, root.appendingPathComponent("build/debug").path)
        XCTAssertEqual(project.configurePresets[1].buildType, "Release")
        XCTAssertEqual(project.buildPresets.last?.configuration, "Release")
    }

    func testEarlierParentWinsAndNullClearsInheritedValues() throws {
        let root = try makeProject(presets: #"""
        {"version": 3, "configurePresets": [
          {"name": "first", "hidden": true, "generator": "Ninja", "cacheVariables": {
            "CMAKE_BUILD_TYPE": "Debug", "CMAKE_C_COMPILER": "clang", "FLAG": true}},
          {"name": "second", "hidden": true, "generator": "Xcode", "cacheVariables": {
            "CMAKE_BUILD_TYPE": "Release", "CMAKE_C_COMPILER": "gcc"}},
          {"name": "child", "inherits": ["first", "second"], "cacheVariables": {"CMAKE_C_COMPILER": null}}
        ]}
        """#)
        let preset = try XCTUnwrap(CMakeProject.load(at: root, environment: [:])?.configurePresets.first)
        XCTAssertEqual(preset.generator, "Ninja")
        XCTAssertEqual(preset.buildType, "Debug")
        XCTAssertEqual(preset.cacheVariables["FLAG"], "TRUE")
        XCTAssertNil(preset.cCompiler)
    }

    func testIncludesUserPresetsEnvironmentAndConditions() throws {
        let root = try makeProject(presets: #"""
        {"version": 9, "include": ["${sourceDir}/cmake/base.json"], "configurePresets": [
          {"name": "mac", "inherits": "base", "condition": {
            "type": "equals", "lhs": "${hostSystemName}", "rhs": "Darwin"}},
          {"name": "windows", "inherits": "base", "condition": false}
        ]}
        """#)
        try write(#"""
        {"version": 3, "configurePresets": [{"name": "base", "hidden": true,
          "environment": {"TOOLS": "$penv{TOOLS}/bin", "CC": "$env{TOOLS}/clang", "CXX": null},
          "cacheVariables": {"CMAKE_CXX_COMPILER": {"type": "FILEPATH", "value": "$env{TOOLS}/clang++"}}}]}
        """#, to: "cmake/base.json", at: root)
        try write(#"""
        {"version": 3, "configurePresets": [{"name": "local", "inherits": "mac",
          "cacheVariables": {"CMAKE_BUILD_TYPE": "RelWithDebInfo"}}]}
        """#, to: "CMakeUserPresets.json", at: root)
        let project = try XCTUnwrap(CMakeProject.load(at: root, environment: ["TOOLS": "/opt/llvm", "CXX": "g++"]))
        XCTAssertTrue(project.errors.isEmpty, project.errors.joined())
        XCTAssertEqual(project.configurePresets.map(\.name), ["mac", "local"])
        XCTAssertEqual(project.configurePresets.last?.cCompiler, "/opt/llvm/bin/clang")
        XCTAssertEqual(project.configurePresets.last?.cxxCompiler, "/opt/llvm/bin/clang++")
        XCTAssertNil(project.configurePresets.last?.environment["CXX"])
        XCTAssertEqual(project.configurePresets.last?.buildType, "RelWithDebInfo")
    }

    func testUserPresetsCanExistWithoutSharedPresets() throws {
        let root = try makeProject()
        try write(Self.selectionPresets, to: "CMakeUserPresets.json", at: root)
        XCTAssertEqual(CMakeProject.load(at: root)?.configurePresets.count, 3)
    }

    func testIncludeAndInheritanceCyclesAreReported() throws {
        let root = try makeProject(presets: #"{"version":4,"include":["other.json"]}"#)
        try write(#"{"version":4,"include":["CMakePresets.json"]}"#, to: "other.json", at: root)
        XCTAssertTrue(CMakeProject.load(at: root)?.errors.first?.contains("cycle") == true)
        try write(#"""
        {"version":3,"configurePresets":[
          {"name":"a","inherits":"b"},{"name":"b","inherits":"a"}]}
        """#, to: "CMakePresets.json", at: root)
        XCTAssertTrue(CMakeProject.load(at: root)?.errors.first?.contains("cycle") == true)
    }

    func testInvalidPresetsDoNotSilentlyProduceSelections() throws {
        let invalid = [
            #"{"version":99}"#,
            #"{"version":3,"configurePresets":[{"name":"a","inherits":"missing"}]}"#,
            #"{"version":3,"configurePresets":[{"name":"a"},{"name":"a"}]}"#,
            #"{"version":3,"configurePresets":[{"name":"a","environment":true}]}"#,
            #"{"version":3,"buildPresets":[{"name":"a"}]}"#,
            #"{"version":4,"include":["missing.json"]}"#,
            #"{"version":3,"configurePresets":[{"name":"a","binaryDir":"${unknown}"}]}"#,
            #"{"version":3,"configurePresets":[{"name":"a","binaryDir":"${sourceDir"}]}"#,
            #"{"version":3,"configurePresets":[{"name":"a","environment":{"CC":"$env{CC}"}}]}"#
        ]
        let root = try makeProject()
        for json in invalid {
            try write(json, to: "CMakePresets.json", at: root)
            let project = try XCTUnwrap(CMakeProject.load(at: root))
            XCTAssertFalse(project.errors.isEmpty, json)
            XCTAssertTrue(project.configurePresets.isEmpty, json)
        }
    }

    func testSharedPresetCannotInheritFromUserPreset() throws {
        let root = try makeProject(presets: #"""
        {"version":3,"configurePresets":[{"name":"shared","inherits":"user"}]}
        """#)
        try write(#"{"version":3,"configurePresets":[{"name":"user"}]}"#, to: "CMakeUserPresets.json", at: root)
        XCTAssertTrue(CMakeProject.load(at: root)?.errors.first?.contains("must include") == true)
    }

    @MainActor
    func testWorkspaceOpenDiscoversProjectAndCloseReleasesModel() async throws {
        let root = try makeProject(presets: Self.selectionPresets)
        let workspace = WorkspaceDocument()
        try workspace.read(from: root, ofType: "public.folder")
        await workspace.cmakeWorkspace?.waitForReload()
        XCTAssertEqual(workspace.cmakeWorkspace?.project?.name, "Example")
        XCTAssertEqual(workspace.cmakeWorkspace?.configurePreset?.name, "debug")
        workspace.close()
        XCTAssertNil(workspace.cmakeWorkspace)
    }

    func testWorkspaceWithoutListFileDoesNotCreateCMakeModels() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let workspace = WorkspaceDocument()
        try workspace.read(from: root, ofType: "public.folder")
        XCTAssertNil(workspace.cmakeWorkspace)
        XCTAssertNil(workspace.cmakeBuildController)
        workspace.close()
    }

    @MainActor
    func testSelectionPersistenceSwitchingAndReload() async throws {
        let root = try makeProject(presets: Self.selectionPresets)
        let suite = "CMakeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = CMakeWorkspace(sourceDirectory: root, defaults: defaults)
        model.reload()
        await model.waitForReload()
        XCTAssertEqual(model.selectedConfigurePreset, "debug")
        XCTAssertEqual(model.buildType, "Debug")
        model.selectConfigurePreset("multi")
        XCTAssertEqual(model.selectedBuildPreset, "multi-release")
        XCTAssertEqual(model.buildType, "Release")
        model.selectConfigurePreset("release")
        XCTAssertEqual(model.selectedBuildPreset, "release-build")
        model.selectConfigurePreset("missing")
        XCTAssertEqual(model.selectedConfigurePreset, "release")
        let reopened = CMakeWorkspace(sourceDirectory: root, defaults: defaults)
        reopened.reload()
        await reopened.waitForReload()
        XCTAssertEqual(reopened.selectedConfigurePreset, "release")
        let original = try String(contentsOf: root.appendingPathComponent("CMakePresets.json"), encoding: .utf8)
        XCTAssertEqual(original, Self.selectionPresets)
        try write(#"{"version":3,"configurePresets":[{"name":"new"}]}"#, to: "CMakePresets.json", at: root)
        reopened.reload()
        await reopened.waitForReload()
        XCTAssertEqual(reopened.selectedConfigurePreset, "new")
        XCTAssertEqual(reopened.selectedBuildPreset, "")
        try FileManager.default.removeItem(at: root.appendingPathComponent("CMakeLists.txt"))
        reopened.reload()
        await reopened.waitForReload()
        XCTAssertNil(reopened.project)
    }

    private func makeProject(presets: String? = nil) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        try write(
            "cmake_minimum_required(VERSION 3.21)\nproject(Example VERSION 1.2 LANGUAGES C CXX)",
            to: "CMakeLists.txt", at: root
        )
        if let presets { try write(presets, to: "CMakePresets.json", at: root) }
        return root
    }

    private func write(_ text: String, to name: String, at root: URL) throws {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static let selectionPresets = #"""
    {"version": 3, "configurePresets": [
      {"name": "base", "hidden": true, "generator": "Ninja", "binaryDir": "${sourceDir}/build/${presetName}",
       "cacheVariables": {"CMAKE_C_COMPILER": "clang", "CMAKE_CXX_COMPILER": "clang++"}},
      {"name": "debug", "displayName": "Clang Debug", "inherits": "base", "cacheVariables": {
        "CMAKE_C_COMPILER": {"type": "FILEPATH", "value": "/usr/bin/clang"},
        "CMAKE_CXX_COMPILER": "/usr/bin/clang++", "CMAKE_BUILD_TYPE": "Debug"}},
      {"name": "release", "inherits": "base", "cacheVariables": {"CMAKE_BUILD_TYPE": "Release"}},
      {"name": "multi", "inherits": "base", "generator": "Ninja Multi-Config"}
    ], "buildPresets": [
      {"name": "debug-build", "configurePreset": "debug"},
      {"name": "release-build", "configurePreset": "release"},
      {"name": "multi-release", "configurePreset": "multi", "configuration": "Release"}
    ]}
    """#
}
