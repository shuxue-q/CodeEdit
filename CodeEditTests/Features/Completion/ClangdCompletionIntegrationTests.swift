//
//  ClangdCompletionIntegrationTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
import CodeEditLanguages
@testable import CodeEditSourceEditor
import LanguageServerProtocol
@testable import CodeEdit

/// The completion pipeline against a real `clangd`: request, rank, accept, and check the document.
///
/// Skipped when `clangd` is not installed. These run headless (no popup window), so they cover what
/// the aggregator and the providers do on accepting an item, not the key handling of the popup.
@MainActor
final class ClangdCompletionIntegrationTests: XCTestCase {
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
        let file = directory.appending(path: "main.cpp")
        try source.write(to: file, atomically: true, encoding: .utf8)

        let configs = await Task.detached { LanguageServerDetector.detectServers() }.value
        guard let binary = configs["cpp"] else { throw XCTSkip("clangd is not installed") }
        let service = try XCTUnwrap(ServiceContainer.resolve(.singleton, LSPService.self))
        let client = try await LSPService.LanguageServerType.createServer(
            for: "cpp", with: binary, workspacePath: directory.path
        )
        let key = LSPService.ClientKey("cpp", directory.path)
        service.languageClients[key] = client
        let document = try CodeFileDocument(for: file, withContentsOf: file, ofType: "public.source-code")
        try await client.openDocument(document)

        let editor = TextViewController(
            string: source,
            language: .cpp,
            configuration: .init(appearance: .init(
                theme: ThemeModel.shared.themes[0].editor.editorTheme,
                font: .monospacedSystemFont(ofSize: 13, weight: .regular),
                wrapLines: false
            )),
            cursorPositions: [],
            highlightProviders: [],
            coordinators: [document.languageServerObjects.textCoordinator]
        )
        editor.loadView()
        editor.textView.setTextStorage(try XCTUnwrap(document.content))

        let aggregator = CompletionAggregator(
            document: document,
            treeSitterClient: TreeSitterClient(),
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

    /// Requests completions at the end of the last `marker` in the document.
    ///
    /// clangd needs a moment to parse a fresh file, and a request that finds nothing within the
    /// deadline shows nothing, as it does for a user: the request is repeated, like another keystroke,
    /// until the server has answered.
    private func complete(
        _ fixture: Fixture,
        after marker: String
    ) async throws -> (offset: Int, result: CodeSuggestionResult?) {
        let offset = (fixture.editor.text as NSString).range(of: marker, options: .backwards).max
        fixture.editor.textView.selectionManager.setSelectedRange(NSRange(location: offset, length: 0))
        var result: CodeSuggestionResult?
        for _ in 0..<20 where result == nil {
            result = await fixture.aggregator.completionSuggestionsResult(
                textView: fixture.editor,
                cursorPosition: CursorPosition(range: NSRange(location: offset, length: 0)),
                trigger: .explicit
            )
            if result == nil { try await Task.sleep(for: .milliseconds(300)) }
        }
        return (offset, result)
    }

    private func accept(_ entry: CodeSuggestionEntry, at offset: Int, in fixture: Fixture) {
        fixture.aggregator.completionWindowApplyCompletion(
            item: entry,
            textView: fixture.editor,
            cursorPosition: CursorPosition(range: NSRange(location: offset, length: 0))
        )
    }

    func testAcceptingAStandardLibraryTypeInsertsItsInclude() async throws {
        let fixture = try await makeFixture(source: "int main() {\n    std::vec\n}\n")
        let (offset, result) = try await complete(fixture, after: "std::vec")

        let items = try XCTUnwrap(result?.items, "clangd offered nothing for std::vec")
        let entry = try XCTUnwrap(
            items.first { $0.label.trimmingCharacters(in: .whitespaces).hasSuffix("vector") },
            "No `vector` among \(items.prefix(10).map(\.label))"
        )
        accept(entry, at: offset, in: fixture)

        // The edit with the include is applied asynchronously only when the item needs resolving.
        let text = fixture.editor.text
        XCTAssertTrue(text.contains("#include <vector>"), "Missing include in:\n\(text)")
        XCTAssertTrue(text.contains("std::vector"), "Missing completed name in:\n\(text)")
        XCTAssertEqual(text.components(separatedBy: "std::vec").count, 2, "The prefix must be replaced, not kept")
    }

    func testAcceptingAFunctionCompletesTheCallAndTheUniqueMatchIsPreselected() async throws {
        let source = "int compute_total(int count, int scale);\nint main() {\n    compute_t\n}\n"
        let fixture = try await makeFixture(source: source)
        let (offset, result) = try await complete(fixture, after: "compute_t")

        let completions = try XCTUnwrap(result)
        let index = try XCTUnwrap(completions.items.firstIndex { $0.label.contains("compute_total") })
        XCTAssertEqual(completions.preselectedIndex, index, "A unique strong match should be preselected")
        accept(completions.items[index], at: offset, in: fixture)

        let text = fixture.editor.text
        XCTAssertTrue(text.contains("compute_total("), "Missing call parentheses in:\n\(text)")
        XCTAssertFalse(text.contains("compute_t\n"), "The prefix must be replaced in:\n\(text)")
    }

    func testAFunctionWithoutParametersGetsEmptyParentheses() async throws {
        let source = "void reset_all();\nint main() {\n    reset_\n}\n"
        let fixture = try await makeFixture(source: source)
        let (offset, result) = try await complete(fixture, after: "reset_")

        let items = try XCTUnwrap(result?.items)
        let entry = try XCTUnwrap(items.first { $0.label.contains("reset_all") })
        accept(entry, at: offset, in: fixture)

        XCTAssertTrue(fixture.editor.text.contains("reset_all()"), "Got:\n\(fixture.editor.text)")
    }

    /// Chain completion on a real clangd: `car.label` is offered where a `std::string` is expected.
    ///
    /// The first request opens the scratch document, which costs a preamble build and can miss the 800 ms
    /// budget; later requests reuse it. The test repeats the request, like a user pressing the key again,
    /// and records how long the first and the following ones took.
    func testChainCompletionOffersAMemberOfTheExpectedTypeFromARealServer() async throws {
        let source = "#include <string>\nstruct Car { std::string label; int doors; };\n"
            + "int main() {\n    Car car;\n    std::string s = \n}\n"
        let fixture = try await makeFixture(source: source)
        let offset = (fixture.editor.text as NSString).range(of: "std::string s = ").max
        fixture.editor.textView.selectionManager.setSelectedRange(NSRange(location: offset, length: 0))

        var durations: [Duration] = []
        var labels: [String] = []
        var items: [CodeSuggestionEntry] = []
        for _ in 0..<20 where !labels.contains("car.label") {
            let start = ContinuousClock.now
            let result = await fixture.aggregator.completionSuggestionsResult(
                textView: fixture.editor,
                cursorPosition: CursorPosition(range: NSRange(location: offset, length: 0)),
                trigger: .chain
            )
            durations.append(ContinuousClock.now - start)
            items = result?.items ?? []
            labels = items.map(\.label)
            if !labels.contains("car.label") { try await Task.sleep(for: .milliseconds(300)) }
        }
        print("CHAIN-LATENCY attempts=\(durations.count) durations=\(durations)")
        XCTAssertTrue(labels.contains("car.label"), "No `car.label` among \(labels.prefix(10))")
        XCTAssertFalse(labels.contains("car.doors"), "An int is not a std::string: \(labels.prefix(10))")
        XCTAssertFalse(labels.contains("car"), "The chain list replaces the regular list: \(labels.prefix(10))")
        XCTAssertTrue(durations.allSatisfy { $0 < .seconds(1) }, "A chain request took too long: \(durations)")

        accept(try XCTUnwrap(items.first { $0.label == "car.label" }), at: offset, in: fixture)
        XCTAssertTrue(
            fixture.editor.text.contains("std::string s = car.label"),
            "Got:\n\(fixture.editor.text)"
        )
    }
}
