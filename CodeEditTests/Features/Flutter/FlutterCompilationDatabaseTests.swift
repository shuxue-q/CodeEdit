//
//  FlutterCompilationDatabaseTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation
import Testing
@testable import CodeEdit

/// ``CMakeCompilationDatabase`` lookups for Flutter workspaces whose CMake project is nested.
/// None of these run CMake: each workspace already holds a database to reuse.
@Suite(.serialized)
struct FlutterCompilationDatabaseTests {
    private func write(_ contents: String, to path: String, in root: URL) throws {
        let file = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: file, atomically: true, encoding: .utf8)
    }

    @Test
    func nestedNativeRootReusesItsDatabase() async throws {
        try await withTempDir { root in
            try write(FlutterProjectTests.pluginPubspec, to: "pubspec.yaml", in: root)
            let listFile = "project(native_add C)\nadd_library(native_add SHARED native_add.c)\n"
            try write(listFile, to: "src/CMakeLists.txt", in: root)
            try write("[]", to: "src/build/compile_commands.json", in: root)

            let source = root.appending(path: "src").standardizedFileURL
            #expect(CMakeCompilationDatabase.sourceDirectory(forWorkspace: root)?.path == source.path)

            await CMakeCompilationDatabase.resetCache()
            let directory = await CMakeCompilationDatabase.databaseDirectory(workspacePath: root.path)
            #expect(directory?.path == source.appending(path: "build").path)
        }
    }

    @Test
    func savedNativeRootSelectsDatabase() async throws {
        try await withTempDir { root in
            try write(FlutterProjectTests.appPubspec, to: "pubspec.yaml", in: root)
            try write("project(Root)", to: "CMakeLists.txt", in: root)
            try write("project(Core)", to: "cpp/CMakeLists.txt", in: root)
            try write("[]", to: "build/compile_commands.json", in: root)
            try write("[]", to: "cpp/build/compile_commands.json", in: root)
            defer {
                UserDefaults.standard.removeObject(forKey: FlutterProject.nativeRootSelectionKey(for: root))
            }

            await CMakeCompilationDatabase.resetCache()
            let rootDatabase = await CMakeCompilationDatabase.databaseDirectory(workspacePath: root.path)
            #expect(rootDatabase?.path == root.appending(path: "build").path)

            FlutterProject.saveNativeRoot(root.appending(path: "cpp"), workspaceDirectory: root)
            await CMakeCompilationDatabase.invalidateCache(workspacePath: root.path)
            let cppDatabase = await CMakeCompilationDatabase.databaseDirectory(workspacePath: root.path)
            #expect(cppDatabase?.path == root.appending(path: "cpp/build").path)
        }
    }

    /// With no saved preset selection the first configure preset's binary directory is used, as
    /// the workspace settings and builds do (OmniExam's `build/macos-debug`).
    @Test
    func unselectedPresetReusesFirstPresetDatabase() async throws {
        try await withTempDir { root in
            try write("project(Root)", to: "CMakeLists.txt", in: root)
            try write("""
            {
              "version": 6,
              "configurePresets": [
                { "name": "dev", "binaryDir": "${sourceDir}/out/dev" },
                { "name": "release", "binaryDir": "${sourceDir}/out/release" }
              ]
            }
            """, to: "CMakePresets.json", in: root)
            try write("[]", to: "out/dev/compile_commands.json", in: root)

            await CMakeCompilationDatabase.resetCache()
            let directory = await CMakeCompilationDatabase.databaseDirectory(workspacePath: root.path)
            #expect(directory?.path == root.appending(path: "out/dev").path)
        }
    }

    @Test
    func flutterProjectWithoutNativeCodeHasNoDatabase() async throws {
        try await withTempDir { root in
            try write(FlutterProjectTests.appPubspec, to: "pubspec.yaml", in: root)
            #expect(CMakeCompilationDatabase.sourceDirectory(forWorkspace: root) == nil)
            await CMakeCompilationDatabase.resetCache()
            #expect(await CMakeCompilationDatabase.databaseDirectory(workspacePath: root.path) == nil)
        }
    }
}
