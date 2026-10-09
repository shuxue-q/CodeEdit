//
//  CMakeCompletionIntegrationTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
import CodeEditLanguages
@testable import CodeEditSourceEditor
import LanguageServerProtocol
@testable import CodeEdit

/// The completion pipeline on a `CMakeLists.txt` with a real `neocmakelsp`, a real syntax tree and a
/// real editor controller: request as the user types, rank, accept, and check the document.
///
/// Skipped when `neocmakelsp` is not installed. Like ``ClangdCompletionIntegrationTests`` these run
/// headless (no popup window), so they cover what the aggregator and the providers do, not the popup's
/// drawing or key handling.
@MainActor
final class CMakeCompletionIntegrationTests: XCTestCase {
    private struct Fixture {
        let directory: URL
        let client: LSPService.LanguageServerType
        let key: LSPService.ClientKey
        let document: CodeFileDocument
        let editor: TextViewController
        let aggregator: CompletionAggregator
    }

    private var fixture: Fixture?

    override func tearDown() async throws {
        if let fixture {
            let service = try? XCTUnwrap(ServiceContainer.resolve(.singleton, LSPService.self))
            service?.languageClients[fixture.key] = nil
            fixture.document.languageServerObjects.textCoordinator.destroy()
            let client = fixture.client
            Task { try? await client.shutdown() }
            try? FileManager.default.removeItem(at: fixture.directory)
        }
        fixture = nil
    }

    private func makeFixture(source: String) async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "CMakeLists.txt")
        try source.write(to: file, atomically: true, encoding: .utf8)

        let configs = await Task.detached { LanguageServerDetector.detectServers() }.value
        guard let binary = configs["cmake"] else { throw XCTSkip("neocmakelsp is not installed") }
        let service = try XCTUnwrap(ServiceContainer.resolve(.singleton, LSPService.self))
        let client = try await LSPService.LanguageServerType.createServer(
            for: "cmake", with: binary, workspacePath: directory.path
        )
        let key = LSPService.ClientKey("cmake", directory.path)
        service.languageClients[key] = client
        let document = try CodeFileDocument(for: file, withContentsOf: file, ofType: "public.source-code")
        try await client.openDocument(document)

        let syntaxTree = TreeSitterClient()
        let editor = TextViewController(
            string: source,
            language: .cmake,
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

        let aggregator = CompletionAggregator(
            document: document,
            treeSitterClient: syntaxTree,
            frequencyStore: InMemoryCompletionFrequencyStore(),
            metrics: CompletionMetricsStore(fileURL: directory.appending(path: "metrics.json"))
        )
        let made = Fixture(
            directory: directory, client: client, key: key, document: document, editor: editor,
            aggregator: aggregator
        )
        fixture = made
        return made
    }

    /// Requests completions the way typing does, at the end of the last `marker` in the document.
    ///
    /// `neocmakelsp` sends about 2 MB (every command and built-in variable, with documentation) for any
    /// request, which can miss the aggregator's 800 ms budget for the server, particularly in a debug build.
    /// The window then opens with the local tables alone and the server's answer is merged in on the next
    /// cursor move, as it is for a user. So the first request is followed by cursor updates, not by new
    /// requests (which would cancel the server's answer), until `isComplete` or `attempts` run out.
    /// A request that is refused outright (a comment, a string) returns `nil` at once.
    private func type(
        _ fixture: Fixture,
        after marker: String,
        until isComplete: ([CodeSuggestionEntry]) -> Bool = { !$0.isEmpty },
        attempts: Int = 40
    ) async throws -> (offset: Int, items: [CodeSuggestionEntry]?) {
        let offset = (fixture.editor.text as NSString).range(of: marker, options: .backwards).max
        let position = CursorPosition(range: NSRange(location: offset, length: 0))
        fixture.editor.textView.selectionManager.setSelectedRange(NSRange(location: offset, length: 0))
        let result = await fixture.aggregator.completionSuggestionsResult(
            textView: fixture.editor,
            cursorPosition: position,
            trigger: .typing
        )
        guard var items = result?.items else { return (offset, nil) }
        for _ in 0..<attempts where !isComplete(items) {
            try await Task.sleep(for: .milliseconds(250))
            if let update = fixture.aggregator.completionSuggestionsUpdated(
                textView: fixture.editor,
                cursorPosition: position
            ) {
                items = update.items
            }
        }
        let top = candidates(items).prefix(8).map { "\($0.label)[\($0.kind),\($0.source)]" }
        print("CMAKE-COMPLETION after \(marker.debugDescription): \(top.joined(separator: " "))")
        return (offset, items)
    }

    private func accept(_ entry: CodeSuggestionEntry, at offset: Int, in fixture: Fixture) {
        fixture.aggregator.completionWindowApplyCompletion(
            item: entry,
            textView: fixture.editor,
            cursorPosition: CursorPosition(range: NSRange(location: offset, length: 0))
        )
    }

    private func selectedRange(_ fixture: Fixture) -> NSRange {
        fixture.editor.textView.selectionManager.textSelections.first?.range ?? NSRange(location: NSNotFound, length: 0)
    }

    /// Whether the server has answered: some row comes from it.
    private func hasServerItems(_ items: [CodeSuggestionEntry]) -> Bool {
        candidates(items).contains { $0.source == .lsp }
    }

    private func candidates(_ items: [CodeSuggestionEntry]) -> [CompletionCandidate] {
        items.compactMap { ($0 as? AggregatedCompletionEntry)?.candidate }
    }

    // MARK: - Tests

    /// `add_` at the start of a line opens the popup with the server's commands and a snippet.
    func testTypingACommandNameOffersCommandsAndSnippets() async throws {
        let fixture = try await makeFixture(source: "cmake_minimum_required(VERSION 3.20)\nproject(demo)\n\nadd_")
        let (_, entries) = try await type(fixture, after: "add_") { items in
            self.candidates(items).contains { $0.label == "add_executable" && $0.source == .lsp }
        }

        let items = candidates(try XCTUnwrap(entries, "Typing `add_` must open the popup"))
        let labels = items.map { "\($0.label):\($0.kind):\($0.source)" }
        XCTAssertTrue(
            items.contains { $0.label == "add_executable" && $0.kind == .function && $0.source == .lsp },
            "The server's command is missing: \(labels.prefix(12))"
        )
        XCTAssertTrue(
            items.contains { $0.label == "add_library" && $0.kind == .function && $0.source == .lsp },
            "The server's command is missing: \(labels.prefix(12))"
        )
        XCTAssertTrue(items.contains { $0.label == "add_executable" && $0.kind == .snippet }, "\(labels.prefix(12))")
        XCTAssertTrue(
            items.prefix(6).allSatisfy { $0.label.lowercased().hasPrefix("add_") },
            "Commands must lead: \(labels.prefix(12))"
        )
        XCTAssertFalse(items.prefix(10).contains { $0.kind == .variable }, "Variables belong inside ${…}")
    }

    /// Accepting the snippet inserts the command with placeholders to tab through.
    func testAcceptingASnippetInsertsPlaceholders() async throws {
        let fixture = try await makeFixture(source: "project(demo)\n\nadd_exe")
        let (offset, items) = try await type(fixture, after: "add_exe", until: hasServerItems)
        let entry = try XCTUnwrap(
            candidates(try XCTUnwrap(items)).first { $0.label == "add_executable" && $0.kind == .snippet },
            "No add_executable snippet among \(items?.map(\.label).prefix(10) ?? [])"
        )
        accept(AggregatedCompletionEntry(candidate: entry), at: offset, in: fixture)

        let text = fixture.editor.text
        XCTAssertTrue(text.hasSuffix("add_executable(target main.cpp)"), "Got:\n\(text)")
        XCTAssertTrue(fixture.editor.isSnippetSessionActive, "The placeholders must be navigable")
        XCTAssertEqual(selectedRange(fixture).length, "target".count, "The first placeholder must be selected")

        fixture.editor.textView.replaceCharacters(in: selectedRange(fixture), with: "app")
        XCTAssertTrue(fixture.editor.moveToSnippetTabStop(), "Tab must move to the next placeholder")
        XCTAssertEqual(selectedRange(fixture).length, "main.cpp".count, "The second placeholder must be selected")
        fixture.editor.textView.replaceCharacters(in: selectedRange(fixture), with: "src/app.cpp")
        XCTAssertTrue(fixture.editor.text.hasSuffix("add_executable(app src/app.cpp)"), fixture.editor.text)
    }

    /// `${CMAKE_` inside `set(…)` opens the popup with variables, and nothing else.
    func testVariableReferenceOffersVariablesOnly() async throws {
        let fixture = try await makeFixture(source: "project(demo)\nset(MY_DIR ${CMAKE_")
        let (_, entries) = try await type(fixture, after: "${CMAKE_", until: hasServerItems)

        let items = candidates(try XCTUnwrap(entries, "Typing `${CMAKE_` must open the popup"))
        let labels = items.map(\.label)
        XCTAssertTrue(labels.contains("CMAKE_SOURCE_DIR"), "\(labels.prefix(12))")
        XCTAssertTrue(labels.contains("CMAKE_CXX_STANDARD"), "\(labels.prefix(12))")
        XCTAssertTrue(items.contains { $0.source == .lsp && $0.kind == .variable }, "No server variable")
        XCTAssertTrue(
            items.prefix(20).allSatisfy { $0.kind == .variable },
            "Variables lead inside ${…}: \(items.prefix(20).map { "\($0.label):\($0.kind)" })"
        )
        XCTAssertFalse(items.contains { $0.kind == .snippet || $0.kind == .keyword }, "\(labels.prefix(12))")
    }

    /// The same inside a quoted argument, where CMake also expands variables.
    func testVariableReferenceInsideQuotesStillOpensThePopup() async throws {
        let fixture = try await makeFixture(source: "project(demo)\nmessage(STATUS \"dir: ${CMAKE_BIN")
        let (_, items) = try await type(fixture, after: "${CMAKE_BIN", until: hasServerItems)
        let labels = try XCTUnwrap(items, "A reference inside quotes must open the popup").map(\.label)
        XCTAssertTrue(labels.contains("CMAKE_BINARY_DIR"), "\(labels.prefix(12))")
    }

    /// `P` after a target offers the keyword arguments.
    func testKeywordArgumentsAreOffered() async throws {
        let source = "project(demo)\nadd_library(app app.cpp)\ntarget_link_libraries(app P"
        let fixture = try await makeFixture(source: source)
        let (_, items) = try await type(fixture, after: "libraries(app P", until: hasServerItems)
        let labels = try XCTUnwrap(items, "Typing `P` in an argument must open the popup").map(\.label)
        XCTAssertTrue(labels.contains("PUBLIC") && labels.contains("PRIVATE"), "\(labels.prefix(12))")
    }

    /// An all-caps `PU` in argument position puts `PUBLIC` first.
    func testCapitalPrefixFavoursKeywordArguments() async throws {
        let source = "project(demo)\nadd_library(app app.cpp)\ntarget_link_libraries(app PU"
        let fixture = try await makeFixture(source: source)
        let (_, items) = try await type(fixture, after: "libraries(app PU", until: hasServerItems)
        let labels = try XCTUnwrap(items, "Typing `PU` in an argument must open the popup").map(\.label)
        XCTAssertEqual(labels.first, "PUBLIC", "An ALL_CAPS prefix favours keyword arguments: \(labels.prefix(8))")
    }

    /// Typing inside a `#` comment does not open the popup.
    func testTypingInACommentOpensNothing() async throws {
        let fixture = try await makeFixture(source: "project(demo)\n# remember to add_")
        let (_, typed) = try await type(fixture, after: "to add_", attempts: 1)
        XCTAssertNil(typed, "A popup must not open while typing a comment")
    }

    /// A path or version in an argument keeps the popup available (it is not member access or a number).
    func testPathsAndVersionsDoNotSuppressThePopup() async throws {
        let fixture = try await makeFixture(source: "project(demo)\nadd_executable(app src/main.cpp")
        let (_, items) = try await type(fixture, after: "src/main.cp", attempts: 12)
        XCTAssertNotNil(items, "`src/main.cp` must not read as a member access")
    }
}
