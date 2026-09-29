//
//  ClangFormatTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 9/28/26.
//

import XCTest
@testable import CodeEdit

final class ClangFormatTests: XCTestCase {

    func testCodeFormatStyleDefaultsToLLVM() throws {
        let settings = try JSONDecoder().decode(
            SettingsData.TextEditingSettings.self,
            from: Data("{}".utf8)
        )
        XCTAssertEqual(settings.codeFormatStyle, .llvm)
    }

    func testCodeFormatStyleRoundTrips() throws {
        var settings = SettingsData.TextEditingSettings()
        settings.codeFormatStyle = .custom
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(SettingsData.TextEditingSettings.self, from: data)
        XCTAssertEqual(decoded.codeFormatStyle, .custom)
    }

    func testFindsNearestClangFormatFile() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let parentConfig = root.appendingPathComponent(".clang-format")
        let nearerConfig = nested.appendingPathComponent("_clang-format")
        try "BasedOnStyle: LLVM\n".write(to: parentConfig, atomically: true, encoding: .utf8)
        try "BasedOnStyle: Google\n".write(to: nearerConfig, atomically: true, encoding: .utf8)

        let file = nested.appendingPathComponent("main.cpp")
        let found = ClangFormatConfig.find(startingAt: file, stoppingAt: root)
        XCTAssertEqual(found?.standardizedFileURL.path, nearerConfig.standardizedFileURL.path)
    }

    func testSearchStopsAtRootWhenNoConfigExists() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("src/main.cpp")
        XCTAssertNil(ClangFormatConfig.find(startingAt: file, stoppingAt: root))
    }

    func testCustomStyleRequiresAConfigFile() {
        XCTAssertThrowsError(
            try ClangFormatRunner.resolveConfig(style: .custom, fileURL: nil)
        ) { error in
            XCTAssertEqual(error as? ClangFormatError, .missingConfig)
        }
    }

    func testBuiltinStyleDoesNotNeedAConfigFile() throws {
        let config = try ClangFormatRunner.resolveConfig(
            style: .google,
            fileURL: URL(fileURLWithPath: "/tmp/main.cpp")
        )
        XCTAssertNil(config)
    }

    func testArgumentsIncludeStyleCursorAndLines() {
        let file = URL(fileURLWithPath: "/proj/main.cpp")
        let config = URL(fileURLWithPath: "/proj/.clang-format")
        let arguments = ClangFormatCommand.arguments(
            style: .custom,
            fileURL: file,
            configFile: config,
            cursorUTF8: 12,
            lineRanges: [3...8]
        )
        XCTAssertEqual(arguments, [
            "--style=file:/proj/.clang-format",
            "--assume-filename=/proj/main.cpp",
            "--cursor=12",
            "--lines=3:8"
        ])
    }

    func testBuiltinStyleArgumentUsesTheClangFormatName() {
        XCTAssertEqual(
            ClangFormatCommand.styleArgument(style: .microsoft, configFile: nil),
            "Microsoft"
        )
        XCTAssertEqual(
            ClangFormatCommand.styleArgument(style: .webKit, configFile: nil),
            "WebKit"
        )
    }

    func testParsesCursorHeader() {
        let stdout = "{ \"Cursor\": 4, \"IncompleteFormat\": false }\nint main() { return 0; }\n"
        let output = ClangFormatRunner.parseOutput(stdout, requestedCursor: true)
        XCTAssertEqual(output.cursorUTF8, 4)
        XCTAssertEqual(output.text, "int main() { return 0; }\n")
    }

    func testUTF8OffsetMapsToUTF16() {
        // "é" is 2 UTF-8 bytes and 1 UTF-16 unit. A mid-character offset stays before it.
        XCTAssertEqual(ClangFormatRunner.utf16Offset(utf8Offset: 1, in: "aé"), 1)
        XCTAssertEqual(ClangFormatRunner.utf16Offset(utf8Offset: 2, in: "aé"), 1)
        XCTAssertEqual(ClangFormatRunner.utf16Offset(utf8Offset: 3, in: "aé"), 2)
    }

    func testLanguageSupport() {
        XCTAssertTrue(ClangFormatLanguage.supports(url: URL(fileURLWithPath: "/tmp/main.CPP")))
        XCTAssertTrue(ClangFormatLanguage.supports(url: URL(fileURLWithPath: "/tmp/main.mm")))
        XCTAssertFalse(ClangFormatLanguage.supports(url: URL(fileURLWithPath: "/tmp/main.swift")))
        XCTAssertFalse(ClangFormatLanguage.supports(url: nil))
    }

    func testLLVMStyleFormatsThroughClangFormat() throws {
        guard let executable = clangFormatPath() else {
            throw XCTSkip("clang-format is not installed")
        }
        let output = try ClangFormatRunner.format(
            ClangFormatRequest(
                source: "int add(int a,int b){return a+b;}\n",
                style: .llvm,
                fileURL: URL(fileURLWithPath: "/tmp/main.cpp"),
                cursorUTF8: 0,
                lineRanges: [],
                executablePath: executable
            )
        )
        XCTAssertEqual(output.text, "int add(int a, int b) { return a + b; }\n")
        XCTAssertEqual(output.cursorUTF8, 0)
    }

    func testCustomStyleReadsProjectClangFormat() throws {
        guard let executable = clangFormatPath() else {
            throw XCTSkip("clang-format is not installed")
        }
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent(".clang-format")
        try "BasedOnStyle: LLVM\nColumnLimit: 20\n".write(to: config, atomically: true, encoding: .utf8)
        let file = root.appendingPathComponent("main.cpp")
        let source = "int add(int alpha, int beta) { return alpha + beta; }\n"
        let output = try ClangFormatRunner.format(
            ClangFormatRequest(
                source: source,
                style: .custom,
                fileURL: file,
                cursorUTF8: nil,
                lineRanges: [],
                executablePath: executable
            )
        )
        XCTAssertGreaterThan(output.text.filter { $0 == "\n" }.count, 1)
        XCTAssertNotEqual(output.text, source)
    }

    private func clangFormatPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/clang-format",
            "/usr/local/bin/clang-format"
        ]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--find", "clang-format"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
            return nil
        }
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codeedit-clang-format-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
