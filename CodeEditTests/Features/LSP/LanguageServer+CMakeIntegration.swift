//
//  LanguageServer+CMakeIntegration.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/10/26.
//

import XCTest
import LanguageServerProtocol

@testable import CodeEdit

/// Integration tests that run a real `neocmakelsp` language server over stdio and verify
/// completion and hover for CMake files, including files opened outside of any workspace.
///
/// These tests are skipped when `neocmakelsp` is not installed on the host machine.
final class LanguageServerCMakeIntegrationTests: XCTestCase {
    typealias LanguageServerType = LanguageServer<CodeFileDocument>

    var tempTestDir: URL!

    override func setUp() {
        continueAfterFailure = false
        do {
            let tempDir = FileManager.default.temporaryDirectory.appending(
                path: "codeedit-cmake-lsp-tests"
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

    /// Locates the `neocmakelsp` executable, skipping the test when it is not installed.
    private func neocmakelspPath() throws -> String {
        var candidates = ["/opt/homebrew/bin/neocmakelsp", "/usr/local/bin/neocmakelsp"]
        let pathComponents = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        candidates.append(contentsOf: pathComponents.map { "\($0)/neocmakelsp" })

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        throw XCTSkip("neocmakelsp is not installed on this machine")
    }

    /// Writes a minimal CMake project file into the temporary directory.
    private func makeCMakeFile() throws -> URL {
        let fileURL = tempTestDir.appending(path: "CMakeLists.txt")
        try """
        cmake_minimum_required(VERSION 3.20)
        project(demo)
        add_exe
        """.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// Starts a real `neocmakelsp stdio` server and requests completion and hover, verifying
    /// the stdio communication channel end to end.
    @MainActor
    func testCMakeCompletionAndHoverOverStdio() async throws {
        let execPath = try neocmakelspPath()
        let fileURL = try makeCMakeFile()

        let binary = LanguageServerBinary(
            execPath: execPath,
            args: ["stdio"],
            env: LanguageServerDetector.userShellEnvironment()
        )
        let server = try await LanguageServerType.createServer(
            for: "cmake",
            with: binary,
            workspacePath: tempTestDir.absolutePath
        )
        defer {
            Task { try? await server.shutdown() }
        }

        XCTAssertNotNil(server.serverCapabilities.completionProvider)
        XCTAssertNotNil(server.serverCapabilities.hoverProvider)

        let codeFile = try CodeFileDocument(
            for: fileURL,
            withContentsOf: fileURL,
            ofType: "CMake script"
        )
        try await server.openDocument(codeFile)

        // Hover documentation is generated on demand from the server's builtin index.
        let hover = try await server.requestHover(
            for: fileURL.lspURI,
            Position(line: 0, character: 3)
        )
        XCTAssertNotNil(hover, "Expected hover documentation for cmake_minimum_required")

        // Completion after "add_exe" on line 2 (0-based) should include "add_executable".
        // The cache is bypassed so a stale response is never reused.
        let completion = try await server.requestCompletion(
            for: fileURL.lspURI,
            position: Position(line: 2, character: 7),
            bypassCache: true
        )
        let labels = completion?.items.map(\.label) ?? []
        XCTAssertTrue(
            labels.contains("add_executable"),
            "Expected add_executable in completion items, got \(labels.prefix(20))"
        )

        try await server.closeDocument(fileURL.lspURI)
    }

    /// Verifies that a file opened without any workspace still gets a language server,
    /// using the file's parent directory as the server's workspace root.
    @MainActor
    func testOpenDocumentWithoutWorkspaceUsesParentDirectory() async throws {
        let execPath = try neocmakelspPath()
        let fileURL = try makeCMakeFile()

        guard let lspService = ServiceContainer.resolve(.singleton, LSPService.self) else {
            XCTFail("LSPService not registered")
            return
        }
        lspService.languageConfigs["cmake"] = LanguageServerBinary(
            execPath: execPath,
            args: ["stdio"],
            env: LanguageServerDetector.userShellEnvironment()
        )

        let codeFile = try CodeFileDocument(
            for: fileURL,
            withContentsOf: fileURL,
            ofType: "CMake script"
        )
        // No workspace contains this file, so opening it must fall back to the parent directory.
        XCTAssertNil(codeFile.findWorkspace())

        lspService.openDocument(codeFile)

        let expectedKey = LSPService.ClientKey("cmake", fileURL.deletingLastPathComponent().absolutePath)
        do {
            let client = try await waitForClient(expectedKey, in: lspService)
            XCTAssertEqual(client.rootPath.absolutePath, fileURL.deletingLastPathComponent().absolutePath)

            try await client.closeDocument(fileURL.lspURI)
            try await client.shutdown()
            lspService.languageClients[expectedKey] = nil
        } catch {
            XCTFail("Failed to talk to the cmake language server: \(error)")
            throw error
        }
    }

    /// Polls the service until the language client for the given key has been created.
    @MainActor
    private func waitForClient(
        _ key: LSPService.ClientKey,
        in lspService: LSPService
    ) async throws -> LanguageServerType {
        for _ in 0..<150 {
            if let client = lspService.languageClients[key] {
                return client
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Timed out waiting for the cmake language server to start")
        throw LSPError.binaryNotFound
    }
}
