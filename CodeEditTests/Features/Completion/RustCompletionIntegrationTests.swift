//
//  RustCompletionIntegrationTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 10/13/26.
//

import XCTest
import CodeEditLanguages
@testable import CodeEditSourceEditor
import LanguageServerProtocol
@testable import CodeEdit

/// A workspace in a temporary directory whose Cargo project sits below the root (as in a Flutter app with a
/// `rust/` folder), with rust-analyzer running on it and one Rust file open in a real editor, wired to the
/// completion aggregator as in the app.
@MainActor
final class RustServerFixture {
    let directory: URL
    let client: LSPService.LanguageServerType
    let key: LSPService.ClientKey
    let document: CodeFileDocument
    let editor: TextViewController
    let aggregator: CompletionAggregator

    /// Where cargo builds for these tests, shared across runs so build scripts compile once. Never inside
    /// the projects the tests read.
    static let targetDirectory = FileManager.default.temporaryDirectory.appending(path: "codeedit-rust-tests-target")

    /// Creates the workspace, starts the server on it and opens `open`.
    /// - Parameters:
    ///   - files: Workspace-relative paths and their contents.
    ///   - open: The file to open in the editor.
    convenience init(files: [String: String], open: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "rust-\(UUID().uuidString)")
        try Self.write(files, to: directory)
        try await self.init(directory: directory, open: open)
    }

    /// Starts the server on an existing workspace and opens `open`.
    init(directory: URL, open: String) async throws {
        let configs = await Task.detached { LanguageServerDetector.detectServers() }.value
        guard let detected = configs["rust"] else { throw XCTSkip("rust-analyzer is not installed") }
        var environment = detected.env ?? [:]
        environment["CARGO_TARGET_DIR"] = Self.targetDirectory.path
        let binary = LanguageServerBinary(execPath: detected.execPath, args: detected.args, env: environment)
        self.directory = directory

        let service = try XCTUnwrap(ServiceContainer.resolve(.singleton, LSPService.self))
        client = try await LSPService.LanguageServerType.createServer(
            for: "rust", with: binary, workspacePath: directory.path
        )
        key = LSPService.ClientKey("rust", directory.path)
        service.languageClients[key] = client
        service.startListeningToEvents(for: key)

        let file = directory.appending(path: open)
        document = try CodeFileDocument(for: file, withContentsOf: file, ofType: "public.source-code")
        try await client.openDocument(document)

        let syntaxTree = TreeSitterClient()
        editor = TextViewController(
            string: (try? String(contentsOf: file, encoding: .utf8)) ?? "",
            language: .rust,
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

    static func write(_ files: [String: String], to directory: URL) throws {
        for (path, contents) in files {
            let url = directory.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Copies the OmniExam Rust sources named by `TEST_RUNNER_RUST_OMNIEXAM_PROJECT` into a temporary
    /// workspace with the same layout (`rust/` plus the Typst package its build script embeds). The project
    /// itself is only read; nothing is built inside it.
    static func copyOmniExam() throws -> URL {
        guard let project = ProcessInfo.processInfo.environment["RUST_OMNIEXAM_PROJECT"] else {
            throw XCTSkip("Set TEST_RUNNER_RUST_OMNIEXAM_PROJECT to the OmniExam repository")
        }
        let source = URL(fileURLWithPath: project)
        let directory = FileManager.default.temporaryDirectory.appending(path: "rust-omniexam-\(UUID().uuidString)")
        let items = [
            "rust/Cargo.toml", "rust/Cargo.lock", "rust/rust-toolchain.toml", "rust/omniexam_typst",
            "typst/omni-exam/typst.toml", "typst/omni-exam/lib.typ", "typst/omni-exam/src"
        ]
        for item in items {
            let destination = directory.appending(path: item)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: source.appending(path: item), to: destination)
        }
        return directory
    }

    /// Stops the server and removes the workspace.
    func tearDown() {
        let service = try? XCTUnwrap(ServiceContainer.resolve(.singleton, LSPService.self))
        service?.stopListeningToEvents(for: key)
        service?.languageClients[key] = nil
        service?.diagnosticsStore.removeWorkspace(directory.path)
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
    /// until `isReady` accepts the list: rust-analyzer answers with little while it loads the workspace.
    func complete(
        after marker: String,
        timeout: Duration = .seconds(180),
        until isReady: ([CodeSuggestionEntry]) -> Bool = { !$0.isEmpty }
    ) async throws -> (offset: Int, result: CodeSuggestionResult?) {
        let offset = offset(after: marker)
        editor.textView.selectionManager.setSelectedRange(NSRange(location: offset, length: 0))
        var result: CodeSuggestionResult?
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            result = await aggregator.completionSuggestionsResult(
                textView: editor,
                cursorPosition: CursorPosition(range: NSRange(location: offset, length: 0)),
                trigger: .explicit
            )
            if let items = result?.items, isReady(items) { break }
            try await Task.sleep(for: .milliseconds(500))
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

    /// Waits until `condition` holds or `timeout` passes.
    func waitUntil(timeout: Duration, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Waits until the editor text contains `text`. Items that need resolving are applied asynchronously.
    func waitForText(containing text: String, timeout: Duration = .seconds(5)) async throws {
        try await waitUntil(timeout: timeout) { self.editor.text.contains(text) }
    }
}

/// Completion from rust-analyzer through CodeEdit's editor: request, filter, accept, auto-import.
///
/// Skipped when rust-analyzer is not installed. The OmniExam cases also need
/// `TEST_RUNNER_RUST_OMNIEXAM_PROJECT=<path>` on the `xcodebuild` command line; they copy its Rust sources and
/// never write to the project. These run headless (no popup window), like the clangd and Dart tests.
@MainActor
final class RustCompletionIntegrationTests: XCTestCase {
    private var fixture: RustServerFixture?

    override func tearDown() async throws {
        fixture?.tearDown()
        fixture = nil
    }

    /// A Cargo workspace two folders below the opened one (`native/rust/`). rust-analyzer looks for a
    /// `Cargo.toml` only at the root and one level down, so it finds this one only as a linked project.
    static let counterSource = """
    pub struct Counter {
        count: u32,
        label: String,
    }

    impl Counter {
        pub fn increment(&mut self, by: u32) {
            self.count += by;
        }

        pub fn total(&self) -> u32 {
            self.
        }

        pub fn names() {
            let m = std::
        }

        pub fn table() {
            let m = HashMa
        }
    }

    """

    static let workspaceFiles: [String: String] = [
        "native/rust/Cargo.toml": "[workspace]\nresolver = \"2\"\nmembers = [\"probe\"]\n",
        "native/rust/probe/Cargo.toml": "[package]\nname = \"probe\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
        "native/rust/probe/src/lib.rs": counterSource
    ]

    private func makeFixture(files: [String: String] = workspaceFiles) async throws -> RustServerFixture {
        let made = try await RustServerFixture(files: files, open: "native/rust/probe/src/lib.rs")
        fixture = made
        return made
    }

    private func labels(_ result: CodeSuggestionResult?) -> [String] {
        result?.items.map(\.label) ?? []
    }

    func testTheNestedWorkspaceIsALinkedProject() async throws {
        let fixture = try await makeFixture()
        guard case .hash(let options) = fixture.client.initializationOptions,
              case .array(let linked) = options["linkedProjects"] else {
            return XCTFail("No linkedProjects in \(fixture.client.initializationOptions)")
        }
        XCTAssertEqual(linked.count, 1)
        if case .string(let path) = linked.first {
            XCTAssertTrue(path.hasSuffix("/native/rust/Cargo.toml"), path)
        }
    }

    func testSelfMembersFilterAndAcceptWithArguments() async throws {
        let fixture = try await makeFixture()
        let (offset, result) = try await fixture.complete(after: "        self.") { items in
            items.contains { $0.label == "count" }
        }
        let names = labels(result)
        XCTAssertTrue(names.contains("count"), "No `count` after `self.` among \(names.prefix(12))")
        XCTAssertTrue(names.contains("label"), "No `label` after `self.` among \(names.prefix(12))")
        XCTAssertTrue(names.contains { $0.hasPrefix("increment") }, "No `increment` among \(names.prefix(12))")
        XCTAssertFalse(names.contains("fn"), "A local snippet after `.`")

        let (typedOffset, filtered) = fixture.type("incr", at: offset)
        let first = try XCTUnwrap(filtered.first, "The list closed after typing `incr`")
        XCTAssertTrue(first.label.hasPrefix("increment"), "Expected increment first: \(filtered.map(\.label))")
        fixture.accept(first, at: typedOffset)
        try await fixture.waitForText(containing: "self.increment(")
        let text = fixture.editor.text
        XCTAssertTrue(text.contains("self.increment(by)"), "Expected the parameter filled in:\n\(text)")
        XCTAssertFalse(text.contains("self.incr\n"), "The prefix must be replaced in:\n\(text)")
    }

    func testStdPathOffersModules() async throws {
        let fixture = try await makeFixture()
        let (_, result) = try await fixture.complete(after: "let m = std::") { items in
            items.contains { $0.label.hasPrefix("collections") }
        }
        let names = labels(result)
        XCTAssertTrue(
            names.contains { $0.hasPrefix("collections") },
            "No `collections` after `std::`: \(names.prefix(12))"
        )
        XCTAssertFalse(names.contains("match"), "A keyword after `::`")
    }

    func testAcceptingAnUnimportedTypeAddsItsUse() async throws {
        let fixture = try await makeFixture()
        let (offset, result) = try await fixture.complete(after: "let m = HashMa") { items in
            items.contains { $0.label == "HashMap" }
        }
        let entry = try XCTUnwrap(
            result?.items.first { $0.label == "HashMap" },
            "No `HashMap` among \(labels(result).prefix(12))"
        )
        XCTAssertTrue(
            entry.detail?.contains("use std::collections::HashMap") == true,
            "The row should name the import: \(entry.detail ?? "nil")"
        )
        fixture.accept(entry, at: offset)

        // rust-analyzer attaches the `use` only on `completionItem/resolve`.
        try await fixture.waitForText(containing: "use std::collections::HashMap;")
        let text = fixture.editor.text
        XCTAssertTrue(text.contains("use std::collections::HashMap;"), "Missing use in:\n\(text)")
        XCTAssertTrue(text.contains("let m = HashMap"), "Missing completed name in:\n\(text)")
    }

    func testTypingReRequestsTheIncompleteList() async throws {
        let fixture = try await makeFixture()
        let (offset, _) = try await fixture.complete(after: "let m = HashMa") { items in
            items.contains { $0.label == "HashMap" }
        }
        XCTAssertTrue(fixture.aggregator.serverList.isIncomplete, "rust-analyzer marks its lists incomplete")
        let (_, items) = fixture.type("p", at: offset)
        XCTAssertTrue(items.contains { $0.label == "HashMap" }, "\(items.map(\.label).prefix(8))")
        XCTAssertEqual(fixture.aggregator.serverList.requestPrefix, "HashMap", "Typing asks the server again")
    }

    // MARK: - OmniExam

    func testOmniExamEngineMembersAndStdPaths() async throws {
        let directory = try RustServerFixture.copyOmniExam()
        let lib = directory.appending(path: "rust/omniexam_typst/src/lib.rs")
        var source = try String(contentsOf: lib, encoding: .utf8)
        let signature = try XCTUnwrap(source.range(of: "pub fn font_count(&self) -> usize {"))
        source.insert(contentsOf: "\n        self.\n        let _ = std::", at: signature.upperBound)
        try source.write(to: lib, atomically: true, encoding: .utf8)

        let made = try await RustServerFixture(directory: directory, open: "rust/omniexam_typst/src/lib.rs")
        fixture = made
        let (_, members) = try await made.complete(after: "        self.", timeout: .seconds(600)) { items in
            items.contains { $0.label.hasPrefix("compile") }
        }
        let names = labels(members)
        XCTAssertTrue(names.contains { $0.hasPrefix("compile") }, "No `compile` after `self.`: \(names.prefix(12))")
        XCTAssertTrue(names.contains { $0.hasPrefix("add_font") }, "No `add_font` after `self.`: \(names.prefix(12))")

        let (_, paths) = try await made.complete(after: "let _ = std::") { items in
            items.contains { $0.label.hasPrefix("sync") }
        }
        XCTAssertTrue(labels(paths).contains { $0.hasPrefix("sync") }, "No `sync` after `std::`")
    }
}
