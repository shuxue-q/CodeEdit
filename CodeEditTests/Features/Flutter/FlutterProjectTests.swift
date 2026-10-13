//
//  FlutterProjectTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation
import Testing
@testable import CodeEdit

@Suite
struct FlutterProjectTests {
    static let appPubspec = """
    name: sample_app
    version: 1.0.0
    dependencies:
      flutter:
        sdk: flutter
    """

    static let pluginPubspec = """
    name: native_add
    flutter:
      plugin:
        platforms:
          macos:
            ffiPlugin: true
    """

    private func write(_ contents: String, to path: String, in root: URL) throws {
        let file = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: file, atomically: true, encoding: .utf8)
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "FlutterProjectTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - Detection

    @Test
    func detectsAppAndFFIPlugin() throws {
        try withTempDir { root in
            #expect(!FlutterProject.isFlutterProject(at: root))
            try write(Self.appPubspec, to: "pubspec.yaml", in: root)
            #expect(FlutterProject.isFlutterProject(at: root))

            try write(Self.pluginPubspec, to: "pubspec.yaml", in: root)
            #expect(FlutterProject.isFlutterProject(at: root))
            let project = try #require(FlutterProject.load(at: root))
            #expect(project.name == "native_add")
            #expect(project.isFFIPlugin)
        }
    }

    @Test
    func pureDartPackageIsNotFlutter() throws {
        try withTempDir { root in
            try write("name: tool\ndependencies:\n  path: ^1.9.0\n", to: "pubspec.yaml", in: root)
            #expect(!FlutterProject.isFlutterProject(at: root))
            #expect(FlutterProject.load(at: root) == nil)
            try write("project(Tool)", to: "CMakeLists.txt", in: root)
            #expect(FlutterProject.activeNativeRoot(workspaceDirectory: root) == nil)
        }
    }

    @Test
    func nameFallsBackToFolderName() throws {
        try withTempDir { root in
            try write("dependencies:\n  flutter:\n    sdk: flutter\n", to: "pubspec.yaml", in: root)
            let project = try #require(FlutterProject.load(at: root))
            #expect(project.name == root.lastPathComponent)
        }
    }

    // MARK: - Native roots

    @Test
    func discoversNativeRootsInOrder() throws {
        try withTempDir { root in
            try write(Self.appPubspec, to: "pubspec.yaml", in: root)
            try write("project(Win)", to: "windows/CMakeLists.txt", in: root)
            try write("project(Core)", to: "cpp/CMakeLists.txt", in: root)
            try write("project(B)", to: "packages/b_pkg/src/CMakeLists.txt", in: root)
            try write("project(A)", to: "packages/a_pkg/src/CMakeLists.txt", in: root)
            try write("// no list file", to: "src/main.c", in: root)
            try write("project(Hidden)", to: "packages/.hidden/src/CMakeLists.txt", in: root)

            let paths = FlutterProject.discoverNativeRoots(in: root)
                .map { FlutterProject.relativePath(of: $0, in: root) }
            #expect(paths == ["cpp", "windows", "packages/a_pkg/src", "packages/b_pkg/src"])

            try write("project(Root)", to: "CMakeLists.txt", in: root)
            let withRoot = FlutterProject.discoverNativeRoots(in: root)
            #expect(withRoot.first?.path == root.path)
            #expect(FlutterProject.load(at: root)?.nativeRoots == withRoot)
        }
    }

    @Test
    func pluginFFILayoutUsesSrc() throws {
        try withTempDir { root in
            try write(Self.pluginPubspec, to: "pubspec.yaml", in: root)
            try write("project(native_add C)", to: "src/CMakeLists.txt", in: root)
            try write("project(runner)", to: "linux/CMakeLists.txt", in: root)
            let defaults = isolatedDefaults()
            let active = FlutterProject.activeNativeRoot(workspaceDirectory: root, defaults: defaults)
            #expect(active?.path == root.appending(path: "src").path)
        }
    }

    @Test
    func savedChoiceWinsWhileItExists() throws {
        try withTempDir { root in
            try write(Self.appPubspec, to: "pubspec.yaml", in: root)
            try write("project(Root)", to: "CMakeLists.txt", in: root)
            try write("project(Core)", to: "cpp/CMakeLists.txt", in: root)
            let defaults = isolatedDefaults()
            #expect(FlutterProject.activeNativeRoot(workspaceDirectory: root, defaults: defaults)
                == root.standardizedFileURL)

            let cpp = root.appending(path: "cpp")
            FlutterProject.saveNativeRoot(cpp, workspaceDirectory: root, defaults: defaults)
            #expect(FlutterProject.savedNativeRoot(workspaceDirectory: root, defaults: defaults) == "cpp")
            #expect(FlutterProject.activeNativeRoot(workspaceDirectory: root, defaults: defaults)
                == cpp.standardizedFileURL)

            // A saved root that disappeared falls back to the first discovered one.
            try FileManager.default.removeItem(at: cpp)
            #expect(FlutterProject.activeNativeRoot(workspaceDirectory: root, defaults: defaults)
                == root.standardizedFileURL)
        }
    }

    @MainActor
    @Test
    func workspaceLoadsAndSelectsRoots() async throws {
        try await withTempDir { root in
            try write(Self.appPubspec, to: "pubspec.yaml", in: root)
            try write("project(Root)", to: "CMakeLists.txt", in: root)
            try write("project(Core)", to: "cpp/CMakeLists.txt", in: root)
            let defaults = isolatedDefaults()
            let workspace = FlutterWorkspace(workspaceDirectory: root, defaults: defaults)
            var changes: [URL?] = []
            workspace.onActiveNativeRootChange = { changes.append($0) }

            workspace.reload()
            await workspace.waitForReload()
            #expect(workspace.project?.name == "sample_app")
            #expect(workspace.activeNativeRoot == root.standardizedFileURL)
            #expect(workspace.displayName(of: root) == "Workspace Root")

            let cpp = root.appending(path: "cpp").standardizedFileURL
            #expect(workspace.displayName(of: cpp) == "cpp/")
            workspace.selectNativeRoot(cpp)
            #expect(workspace.activeNativeRoot == cpp)
            #expect(changes == [root.standardizedFileURL, cpp])
            #expect(FlutterProject.savedNativeRoot(workspaceDirectory: root, defaults: defaults) == "cpp")

            // Folders that are not discovered roots are rejected.
            workspace.selectNativeRoot(root.appending(path: "lib"))
            #expect(workspace.activeNativeRoot == cpp)
            workspace.cancel()
        }
    }

    // MARK: - SDK

    @Test
    func sdkResolvesSymlinkAndReadsVersion() throws {
        try withTempDir { root in
            let sdk = root.appending(path: "flutter")
            try write("#!/bin/sh\n", to: "flutter/bin/flutter", in: root)
            let executable = sdk.appending(path: "bin/flutter")
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            try write(
                #"{"frameworkVersion":"3.47.0","channel":"stable","dartSdkVersion":"3.13.0"}"#,
                to: "flutter/bin/cache/flutter.version.json",
                in: root
            )
            let link = root.appending(path: "local/bin/flutter")
            try FileManager.default.createDirectory(
                at: link.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: executable)

            let found = try #require(FlutterSDK.sdk(forExecutable: link))
            #expect(found.rootDirectory.resolvingSymlinksInPath() == sdk.resolvingSymlinksInPath())
            #expect(found.version == "3.47.0")
            #expect(found.channel == "stable")
            #expect(found.dartVersion == "3.13.0")

            // `<sdk>/version` takes precedence when present.
            try write("3.48.0-1.0.pre\n", to: "flutter/version", in: root)
            #expect(FlutterSDK.sdk(forExecutable: link)?.version == "3.48.0-1.0.pre")
        }
    }

    @Test
    func sdkRejectsExecutableOutsideBin() throws {
        try withTempDir { root in
            try write("#!/bin/sh\n", to: "tools/flutter", in: root)
            #expect(FlutterSDK.sdk(forExecutable: root.appending(path: "tools/flutter")) == nil)
        }
    }
}
