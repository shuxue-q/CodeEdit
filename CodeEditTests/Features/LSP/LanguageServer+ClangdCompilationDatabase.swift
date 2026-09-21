//
//  LanguageServer+ClangdCompilationDatabase.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 9/11/26.
//

import XCTest
import LanguageServerProtocol

@testable import CodeEdit

/// Tests for ``CMakeCompilationDatabase`` and the clangd launch integration in ``LSPService``.
///
/// The integration tests run a real `cmake` configure and a real `clangd` server over stdio, and
/// are skipped when either tool is not installed on the host machine.
final class ClangdCompilationDatabaseTests: XCTestCase {
    typealias LanguageServerType = LanguageServer<CodeFileDocument>

    var tempTestDir: URL!

    override func setUp() {
        continueAfterFailure = false
        do {
            let tempDir = FileManager.default.temporaryDirectory.appending(
                path: "codeedit-clangd-db-tests"
            )
            if FileManager.default.fileExists(atPath: tempDir.absoluteURL.path()) {
                try FileManager.default.removeItem(at: tempDir)
            }
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            tempTestDir = tempDir
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempTestDir)
    }

    // MARK: - Helpers

    /// Locates an executable, skipping the test when it is not installed.
    private func toolPath(_ name: String) throws -> String {
        var candidates = ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"]
        let pathComponents = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        candidates.append(contentsOf: pathComponents.map { "\($0)/\(name)" })

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        throw XCTSkip("\(name) is not installed on this machine")
    }

    private func makeCMakePreset(name: String, binaryDirectory: String?) -> CMakePreset {
        CMakePreset(
            name: name,
            displayName: nil,
            generator: nil,
            binaryDirectory: binaryDirectory,
            toolchainFile: nil,
            configurePreset: nil,
            configuration: nil,
            cacheVariables: [:],
            environment: [:]
        )
    }

    /// Writes a minimal C CMake project into the temporary directory.
    private func makeCProject() throws -> URL {
        let listFile = tempTestDir.appending(path: "CMakeLists.txt")
        try """
        cmake_minimum_required(VERSION 3.20)
        project(demo C)
        add_executable(demo main.c)
        """.write(to: listFile, atomically: true, encoding: .utf8)

        let sourceFile = tempTestDir.appending(path: "main.c")
        try """
        struct Point { int x; int y; };

        int main(void) {
            struct Point point = {1, 2};
            point.
            return 0;
        }
        """.write(to: sourceFile, atomically: true, encoding: .utf8)
        return sourceFile
    }

    /// Polls clangd for completions after "point." until the struct members appear,
    /// covering indexing time on slower machines.
    private func pollMemberCompletions(
        client: LanguageServerType,
        sourceFile: URL
    ) async throws -> [String] {
        var labels: [String] = []
        for _ in 0..<100 {
            let completion = try await client.requestCompletion(
                for: sourceFile.lspURI,
                position: Position(line: 4, character: 10),
                bypassCache: true
            )
            // clangd pads member labels (e.g. " x"), so compare trimmed labels.
            labels = completion?.items.map { $0.label.trimmingCharacters(in: .whitespaces) } ?? []
            if labels.contains("x") && labels.contains("y") { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        return labels
    }

    // MARK: - Unit Tests

    func testBuildDirectoryDefaultsToBuildFolder() {
        let directory = CMakeCompilationDatabase.buildDirectory(
            sourceDirectory: tempTestDir,
            configurePreset: nil
        )
        XCTAssertEqual(directory, tempTestDir.appending(path: "build"))
    }

    func testBuildDirectoryResolvesPresetRelativeBinaryDirectory() {
        let preset = makeCMakePreset(name: "dev", binaryDirectory: "out/build")
        let directory = CMakeCompilationDatabase.buildDirectory(
            sourceDirectory: tempTestDir,
            configurePreset: preset
        )
        XCTAssertEqual(directory, tempTestDir.appending(path: "out/build"))
    }

    func testBuildDirectoryUsesAbsolutePresetBinaryDirectory() {
        let preset = makeCMakePreset(name: "dev", binaryDirectory: "/tmp/custom-build")
        let directory = CMakeCompilationDatabase.buildDirectory(
            sourceDirectory: tempTestDir,
            configurePreset: preset
        )
        XCTAssertEqual(directory.path, "/tmp/custom-build")
    }

    /// An existing `compile_commands.json` must be reused without invoking CMake.
    func testDatabaseDirectoryReusesExistingDatabase() async throws {
        _ = try makeCProject()
        let buildDirectory = tempTestDir.appending(path: "build")
        try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)
        try "[]".write(
            to: buildDirectory.appending(path: "compile_commands.json"),
            atomically: true,
            encoding: .utf8
        )

        await CMakeCompilationDatabase.resetCache()
        let directory = await CMakeCompilationDatabase.databaseDirectory(
            workspacePath: tempTestDir.absolutePath
        )
        XCTAssertEqual(try XCTUnwrap(directory).path, buildDirectory.path)
    }

    /// A compilation database sitting next to another project's CMake cache must not be reused.
    func testDatabaseDirectoryDoesNotReuseForeignCache() async throws {
        let sourceFile = try makeCProject()
        let buildDirectory = tempTestDir.appending(path: "build")
        try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)
        try #"[{"directory":"/other","command":"cc","file":"FOREIGN_DATABASE_MARKER"}]"#.write(
            to: buildDirectory.appending(path: "compile_commands.json"),
            atomically: true,
            encoding: .utf8
        )
        try """
        CMAKE_HOME_DIRECTORY:INTERNAL=/Users/other/Supersonic Transport/panair
        CMAKE_CACHEFILE_DIR:INTERNAL=/Users/other/Supersonic Transport/panair/build
        """.write(
            to: buildDirectory.appending(path: "CMakeCache.txt"),
            atomically: true,
            encoding: .utf8
        )

        await CMakeCompilationDatabase.resetCache()
        let directory = await CMakeCompilationDatabase.databaseDirectory(
            workspacePath: tempTestDir.absolutePath
        )

        guard let directory else {
            // cmake is not installed: the foreign database must still not be reused.
            return
        }
        let contents = try String(
            contentsOf: directory.appending(path: "compile_commands.json"),
            encoding: .utf8
        )
        XCTAssertFalse(contents.contains("FOREIGN_DATABASE_MARKER"), contents)
        XCTAssertTrue(contents.contains(sourceFile.path), "regenerated database should list main.c")
    }

    /// Non-CMake workspaces never get a compilation database.
    func testDatabaseDirectoryReturnsNilWithoutCMakeProject() async {
        await CMakeCompilationDatabase.resetCache()
        let directory = await CMakeCompilationDatabase.databaseDirectory(
            workspacePath: tempTestDir.absolutePath
        )
        XCTAssertNil(directory)
    }

    // MARK: - Integration Tests

    /// CMake configure must produce a `compile_commands.json` referencing the project's sources.
    func testGeneratesCompilationDatabaseWithCMake() async throws {
        _ = try toolPath("cmake")
        let sourceFile = try makeCProject()

        await CMakeCompilationDatabase.resetCache()
        let directory = await CMakeCompilationDatabase.databaseDirectory(
            workspacePath: tempTestDir.absolutePath
        )

        let buildDirectory = try XCTUnwrap(directory)
        let databaseFile = buildDirectory.appending(path: "compile_commands.json")
        let contents = try String(contentsOf: databaseFile, encoding: .utf8)
        XCTAssertTrue(contents.contains(sourceFile.path), "compile_commands.json should list main.c")
    }

    /// Starting the C language server for a CMake workspace must launch clangd with
    /// `--compile-commands-dir`, and the resulting server must answer completion requests.
    @MainActor
    func testClangdStartsWithCompilationDatabase() async throws {
        _ = try toolPath("cmake") // generation runs through the detector, this only gates the test
        let clangdPath = try toolPath("clangd")
        let sourceFile = try makeCProject()

        guard let lspService = ServiceContainer.resolve(.singleton, LSPService.self) else {
            XCTFail("LSPService not registered")
            return
        }
        lspService.languageConfigs["c"] = LanguageServerBinary(
            execPath: clangdPath,
            args: [],
            env: LanguageServerDetector.userShellEnvironment()
        )
        defer { lspService.languageConfigs["c"] = nil }

        await CMakeCompilationDatabase.resetCache()
        let workspacePath = tempTestDir.absolutePath
        let client = try await lspService.startServer(for: "c", workspacePath: workspacePath)
        defer {
            Task {
                try? await client.shutdown()
                await MainActor.run {
                    lspService.languageClients[.init("c", workspacePath)] = nil
                }
            }
        }

        let databaseArgument = client.binary.args.first { $0.hasPrefix("--compile-commands-dir=") }
        XCTAssertNotNil(databaseArgument, "clangd should receive --compile-commands-dir")
        let expectedBuildPath = tempTestDir.appending(path: "build").standardizedFileURL.path
        XCTAssertEqual(databaseArgument, "--compile-commands-dir=\(expectedBuildPath)")

        // Semantic tokens are required for clangd-powered semantic highlighting.
        XCTAssertNotNil(client.highlightMap, "clangd should advertise semantic tokens")

        let codeFile = try CodeFileDocument(
            for: sourceFile,
            withContentsOf: sourceFile,
            ofType: "public.c-source"
        )
        try await client.openDocument(codeFile)

        // Completion after "point." should offer the struct members once clangd has parsed the
        // file. Poll briefly to cover indexing time on slower machines.
        let labels = try await pollMemberCompletions(client: client, sourceFile: sourceFile)
        XCTAssertTrue(
            labels.contains("x") && labels.contains("y"),
            "Expected struct members in completion items, got \(labels.prefix(20))"
        )

        try await client.closeDocument(sourceFile.lspURI)
    }
}
