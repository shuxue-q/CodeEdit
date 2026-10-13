//
//  DartCompletionIntegrationTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 10/13/26.
//

import XCTest
import CodeEditLanguages
@testable import CodeEditSourceEditor
import LanguageServerProtocol
@testable import CodeEdit

/// A Dart package in a temporary directory with the Dart analysis server running on it and one of its files
/// open in a real editor, wired to the completion aggregator as in the app.
@MainActor
final class DartServerFixture {
    let directory: URL
    let client: LSPService.LanguageServerType
    let key: LSPService.ClientKey
    let document: CodeFileDocument
    let editor: TextViewController
    let aggregator: CompletionAggregator

    /// Creates the package, starts the server on it and opens `open`.
    /// - Parameters:
    ///   - files: Package-relative paths and their contents. `pubspec.yaml` is added when missing.
    ///   - open: The file to open in the editor.
    ///   - packageConfig: A `.dart_tool/package_config.json` to resolve `package:` imports with.
    init(files: [String: String], open: String, packageConfig: Data? = nil) async throws {
        let configs = await Task.detached { LanguageServerDetector.detectServers() }.value
        guard let binary = configs["dart"] else { throw XCTSkip("No Dart SDK is installed") }

        directory = FileManager.default.temporaryDirectory.appending(path: "dart-\(UUID().uuidString)")
        try Self.write(files: files, packageConfig: packageConfig, to: directory)

        let service = try XCTUnwrap(ServiceContainer.resolve(.singleton, LSPService.self))
        client = try await LSPService.LanguageServerType.createServer(
            for: "dart", with: binary, workspacePath: directory.path
        )
        key = LSPService.ClientKey("dart", directory.path)
        service.languageClients[key] = client
        service.startListeningToEvents(for: key)

        let file = directory.appending(path: open)
        document = try CodeFileDocument(for: file, withContentsOf: file, ofType: "public.source-code")
        try await client.openDocument(document)

        let syntaxTree = TreeSitterClient()
        editor = TextViewController(
            string: files[open] ?? "",
            language: .dart,
            configuration: .init(appearance: .init(
                theme: ThemeModel.shared.themes[0].editor.editorTheme,
                font: .monospacedSystemFont(ofSize: 13, weight: .regular),
                wrapLines: false
            )),
            cursorPositions: [],
            highlightProviders: [syntaxTree],
            coordinators: [document.languageServerObjects.textCoordinator]
        )
        editor.loadView()
        editor.textView.setTextStorage(try XCTUnwrap(document.content))

        aggregator = CompletionAggregator(
            document: document,
            treeSitterClient: syntaxTree,
            frequencyStore: InMemoryCompletionFrequencyStore(),
            metrics: CompletionMetricsStore(fileURL: directory.appending(path: "metrics.json"))
        )
    }

    private static func write(files: [String: String], packageConfig: Data?, to directory: URL) throws {
        var files = files
        if files["pubspec.yaml"] == nil {
            files["pubspec.yaml"] = "name: codeedit_probe\nenvironment:\n  sdk: ^3.0.0\n"
        }
        for (path, contents) in files {
            let url = directory.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        if let packageConfig {
            let toolDirectory = directory.appending(path: ".dart_tool")
            try FileManager.default.createDirectory(at: toolDirectory, withIntermediateDirectories: true)
            try packageConfig.write(to: toolDirectory.appending(path: "package_config.json"))
        }
    }

    /// The package configuration of the project named by `TEST_RUNNER_DART_FLUTTER_PROJECT`, with relative
    /// roots made absolute so a scratch package elsewhere resolves the same `package:` imports.
    static func flutterPackageConfig() throws -> Data {
        guard let project = ProcessInfo.processInfo.environment["DART_FLUTTER_PROJECT"] else {
            throw XCTSkip("Set TEST_RUNNER_DART_FLUTTER_PROJECT to a Flutter project with resolved packages")
        }
        let toolDirectory = URL(fileURLWithPath: project).appending(path: ".dart_tool", directoryHint: .isDirectory)
        let data = try Data(contentsOf: toolDirectory.appending(path: "package_config.json"))
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let packages = try XCTUnwrap(json["packages"] as? [[String: Any]])
        json["packages"] = packages.map { package in
            var package = package
            if let rootUri = package["rootUri"] as? String, !rootUri.contains(":") {
                package["rootUri"] = URL(string: rootUri, relativeTo: toolDirectory)?.absoluteURL.absoluteString
            }
            return package
        }
        return try JSONSerialization.data(withJSONObject: json)
    }

    /// Stops the server and removes the package.
    func tearDown() {
        let service = try? XCTUnwrap(ServiceContainer.resolve(.singleton, LSPService.self))
        service?.stopListeningToEvents(for: key)
        service?.languageClients[key] = nil
        document.languageServerObjects.textCoordinator.destroy()
        let client = client
        Task { try? await client.shutdown() }
        try? FileManager.default.removeItem(at: directory)
    }

    /// The document offset right after the last `marker`.
    func offset(after marker: String) -> Int {
        (editor.text as NSString).range(of: marker, options: .backwards).max
    }

    /// Requests completions at the end of the last `marker`, repeating the request (like another keystroke)
    /// until `isReady` accepts the list: the server answers with nothing while it analyzes a fresh file.
    func complete(
        after marker: String,
        until isReady: ([CodeSuggestionEntry]) -> Bool = { !$0.isEmpty }
    ) async throws -> (offset: Int, result: CodeSuggestionResult?) {
        let offset = offset(after: marker)
        editor.textView.selectionManager.setSelectedRange(NSRange(location: offset, length: 0))
        var result: CodeSuggestionResult?
        for _ in 0..<40 {
            result = await aggregator.completionSuggestionsResult(
                textView: editor,
                cursorPosition: CursorPosition(range: NSRange(location: offset, length: 0)),
                trigger: .explicit
            )
            if let items = result?.items, isReady(items) { break }
            try await Task.sleep(for: .milliseconds(300))
        }
        return (offset, result)
    }

    /// Types `text` at `offset` and refreshes the open list, as the popup does on a keystroke.
    func type(_ text: String, at offset: Int) -> (offset: Int, items: [CodeSuggestionEntry]) {
        editor.textView.replaceCharacters(in: NSRange(location: offset, length: 0), with: text)
        let newOffset = offset + (text as NSString).length
        editor.textView.selectionManager.setSelectedRange(NSRange(location: newOffset, length: 0))
        let update = aggregator.completionSuggestionsUpdated(
            textView: editor,
            cursorPosition: CursorPosition(range: NSRange(location: newOffset, length: 0))
        )
        return (newOffset, update?.items ?? [])
    }

    /// Accepts `entry` as pressing Return in the popup does.
    func accept(_ entry: CodeSuggestionEntry, at offset: Int) {
        aggregator.completionWindowApplyCompletion(
            item: entry,
            textView: editor,
            cursorPosition: CursorPosition(range: NSRange(location: offset, length: 0))
        )
    }

    /// Waits until the editor text contains `text`. Items that need resolving are applied asynchronously.
    func waitForText(containing text: String, timeout: Duration = .seconds(3)) async throws {
        try await waitUntil(timeout: timeout) { self.editor.text.contains(text) }
    }

    /// Waits until `condition` holds or `timeout` passes.
    func waitUntil(timeout: Duration, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}

/// Completion from the Dart analysis server through CodeEdit's editor: request, filter, accept, auto-import.
///
/// Skipped when no Dart SDK is found. The Flutter cases (`context.`, `Text(`) also need a Flutter project
/// with resolved packages, given as `TEST_RUNNER_DART_FLUTTER_PROJECT=<path>` on the `xcodebuild` command
/// line; the project is only read. These run headless (no popup window), like the clangd integration tests.
@MainActor
final class DartCompletionIntegrationTests: XCTestCase {
    private var fixture: DartServerFixture?

    override func tearDown() async throws {
        fixture?.tearDown()
        fixture = nil
    }

    private func makeFixture(
        files: [String: String],
        open: String,
        packageConfig: Data? = nil
    ) async throws -> DartServerFixture {
        let made = try await DartServerFixture(files: files, open: open, packageConfig: packageConfig)
        fixture = made
        return made
    }

    func testAcceptingAnUnimportedSymbolAddsItsImport() async throws {
        let fixture = try await makeFixture(
            files: ["lib/main.dart": "void main() {\n  Uint8Li\n}\n"],
            open: "lib/main.dart"
        )
        let (offset, result) = try await fixture.complete(after: "Uint8Li") { items in
            items.contains { $0.label == "Uint8List" }
        }
        let items = try XCTUnwrap(result?.items, "The Dart server offered nothing for Uint8Li")
        let entry = try XCTUnwrap(
            items.first { $0.label == "Uint8List" },
            "No `Uint8List` among \(items.prefix(10).map(\.label))"
        )
        fixture.accept(entry, at: offset)

        // The import is attached only by `completionItem/resolve`, so the item is applied after it answers.
        try await fixture.waitForText(containing: "import 'dart:typed_data';")
        let text = fixture.editor.text
        XCTAssertTrue(text.contains("import 'dart:typed_data';"), "Missing import in:\n\(text)")
        XCTAssertTrue(text.contains("  Uint8List"), "Missing completed name in:\n\(text)")
        XCTAssertFalse(text.contains("Uint8Li\n"), "The prefix must be replaced in:\n\(text)")
    }

    func testMemberListFiltersWhileTypingAndAccepts() async throws {
        let fixture = try await makeFixture(
            files: ["lib/main.dart": "void main() {\n  final name = 'abc';\n  name.\n}\n"],
            open: "lib/main.dart"
        )
        let (offset, result) = try await fixture.complete(after: "name.")
        let labels = try XCTUnwrap(result?.items).map(\.label)
        XCTAssertTrue(labels.contains("length"), "No `length` after `name.` among \(labels.prefix(10))")

        let (typedOffset, filtered) = fixture.type("toUp", at: offset)
        let first = try XCTUnwrap(filtered.first, "The list closed after typing `toUp`")
        XCTAssertTrue(first.label.hasPrefix("toUpperCase"), "Expected toUpperCase first: \(filtered.map(\.label))")
        fixture.accept(first, at: typedOffset)
        try await fixture.waitForText(containing: "name.toUpperCase()")
        XCTAssertTrue(fixture.editor.text.contains("name.toUpperCase()"), "Got:\n\(fixture.editor.text)")
    }

    // MARK: - Flutter

    private static let flutterSource = """
    import 'package:flutter/material.dart';

    void members(BuildContext context) {
      context.
    }

    Widget label() => Text();

    void statement() {
      Te
    }

    """

    func testFlutterMembersAndNamedArguments() async throws {
        let fixture = try await makeFixture(
            files: ["lib/probe.dart": Self.flutterSource],
            open: "lib/probe.dart",
            packageConfig: try DartServerFixture.flutterPackageConfig()
        )

        let (memberOffset, members) = try await fixture.complete(after: "context.") { items in
            items.contains { $0.label == "mounted" }
        }
        fixture.accept(try XCTUnwrap(members?.items.first { $0.label == "mounted" }), at: memberOffset)
        try await fixture.waitForText(containing: "context.mounted")
        XCTAssertTrue(fixture.editor.text.contains("context.mounted"), "Got:\n\(fixture.editor.text)")

        let (argumentOffset, arguments) = try await fixture.complete(after: "Text(") { items in
            items.contains { $0.label.hasPrefix("style") }
        }
        let style = try XCTUnwrap(
            arguments?.items.first { $0.label.hasPrefix("style") },
            "No `style:` among \(arguments?.items.prefix(10).map(\.label) ?? [])"
        )
        fixture.accept(style, at: argumentOffset)
        try await fixture.waitForText(containing: "Text(style:")
        XCTAssertTrue(fixture.editor.text.contains("Text(style:"), "Got:\n\(fixture.editor.text)")
    }

    /// A two-letter prefix in a Flutter file gets the largest list the server sends. Once the server is warm,
    /// its items must make the first list (the 150 ms grace window), not arrive late.
    func testLargeFlutterListMakesTheFirstList() async throws {
        let fixture = try await makeFixture(
            files: ["lib/probe.dart": Self.flutterSource],
            open: "lib/probe.dart",
            packageConfig: try DartServerFixture.flutterPackageConfig()
        )
        func serverItems(_ items: [CodeSuggestionEntry]) -> Int {
            items.filter { ($0 as? AggregatedCompletionEntry)?.candidate.source == .lsp }.count
        }
        _ = try await fixture.complete(after: "  Te") { serverItems($0) > 0 }

        var durations: [Duration] = []
        var counts: [Int] = []
        for _ in 0..<5 {
            let start = ContinuousClock.now
            let (_, result) = try await fixture.complete(after: "  Te")
            durations.append(ContinuousClock.now - start)
            counts.append(serverItems(result?.items ?? []))
        }
        print("DART-LATENCY serverItems=\(counts) durations=\(durations)")
        XCTAssertTrue(counts.allSatisfy { $0 > 100 }, "Server items missing from the first list: \(counts)")
        XCTAssertTrue(durations.allSatisfy { $0 < .seconds(1) }, "A warm request took too long: \(durations)")
    }
}
