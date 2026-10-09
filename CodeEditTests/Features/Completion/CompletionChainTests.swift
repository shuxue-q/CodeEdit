//
//  CompletionChainTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
import CodeEditLanguages
@testable import CodeEditSourceEditor
import LanguageServerProtocol
@testable import CodeEdit

/// A chain request through the aggregator: the regular list is replaced by chains, within the budget.
@MainActor
final class CompletionChainTests: XCTestCase {
    private var directory: URL!
    private var document: CodeFileDocument?

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        document = nil
        try? FileManager.default.removeItem(at: directory)
    }

    /// Offers a `Car car` and an `int count`, as a language server would at `std::string s = `.
    private final class SymbolProvider: CompletionProvider {
        let source: CompletionSource = .lsp
        let deadline: Duration = .zero

        func candidates(
            for context: CodeEdit.CompletionContext,
            textView: TextViewController
        ) async -> [CompletionCandidate] {
            [("count", "int"), ("car", "Car")].enumerated().map { index, entry in
                let item = CompletionItem(label: " " + entry.0, kind: .field, detail: entry.1, insertText: entry.0)
                return CompletionCandidate(
                    id: "symbol.\(entry.0)", label: entry.0, filterText: entry.0,
                    sortText: String(format: "%03d", index), kind: .variable, source: .lsp, detail: entry.1,
                    payload: .lsp(item)
                )
            }
        }

        func apply(_ candidate: CompletionCandidate, textView: TextViewController, cursorPosition: CursorPosition?) { }
    }

    /// What a request produced, and what is needed to accept one of its rows.
    private struct Outcome {
        let labels: [String]
        let elapsed: Duration
        let items: [CodeSuggestionEntry]
        let aggregator: CompletionAggregator
        let editor: TextViewController
    }

    private func request(
        trigger: CodeSuggestionTrigger,
        server: FakeChainScratchServer?
    ) async throws -> Outcome {
        let source = "void f() {\n    std::string s = "
        let file = directory.appending(path: "chain.cpp")
        try source.write(to: file, atomically: true, encoding: .utf8)
        let document = try CodeFileDocument(for: file, withContentsOf: file, ofType: "public.source-code")
        self.document = document
        let editor = TextViewController(
            string: source,
            language: .cpp,
            configuration: .init(appearance: .init(
                theme: ThemeModel.shared.themes[0].editor.editorTheme,
                font: .monospacedSystemFont(ofSize: 13, weight: .regular),
                wrapLines: false
            )),
            cursorPositions: [],
            highlightProviders: []
        )
        editor.loadView()
        let aggregator = CompletionAggregator(
            document: document,
            treeSitterClient: TreeSitterClient(),
            frequencyStore: InMemoryCompletionFrequencyStore(),
            metrics: CompletionMetricsStore(fileURL: directory.appending(path: "metrics.json")),
            additionalProviders: [SymbolProvider()],
            expectedTypeSource: { _, _ in TypeText.parse("std::string") },
            receiverTypeSource: { _, _ in nil },
            chainServerFactory: { server }
        )
        let start = ContinuousClock.now
        let result = await aggregator.completionSuggestionsResult(
            textView: editor,
            cursorPosition: CursorPosition(range: NSRange(location: editor.textView.textStorage.length, length: 0)),
            trigger: trigger
        )
        let items = result?.items ?? []
        return Outcome(
            labels: items.map(\.label),
            elapsed: ContinuousClock.now - start,
            items: items,
            aggregator: aggregator,
            editor: editor
        )
    }

    private func carServer() -> FakeChainScratchServer {
        let server = FakeChainScratchServer()
        server.membersAfter["car."] = [
            (CompletionItem(label: " label", kind: .field, detail: "std::string", insertText: "label"), 1),
            (CompletionItem(label: " doors", kind: .field, detail: "int", insertText: "doors"), 1)
        ]
        return server
    }

    func testAChainRequestShowsChainsInsteadOfTheRegularList() async throws {
        let labels = try await request(trigger: .chain, server: carServer()).labels
        XCTAssertEqual(labels.first, "car.label", "Got \(labels)")
        XCTAssertFalse(labels.contains("count"), "The regular list is replaced by the chains: \(labels)")
    }

    func testARegularRequestIsUnaffected() async throws {
        let server = carServer()
        let labels = try await request(trigger: .explicit, server: server).labels
        XCTAssertTrue(labels.contains("count") && labels.contains("car"), "Got \(labels)")
        XCTAssertFalse(labels.contains("car.label"))
        XCTAssertTrue(server.updates.isEmpty, "Only chain requests may touch the scratch document")
    }

    func testWithoutAnyChainTheRegularListIsShown() async throws {
        let labels = try await request(trigger: .chain, server: FakeChainScratchServer()).labels
        XCTAssertTrue(labels.contains("count") && labels.contains("car"), "Got \(labels)")
        let withoutServer = try await request(trigger: .chain, server: nil).labels
        XCTAssertTrue(withoutServer.contains("count"), "Got \(withoutServer)")
    }

    func testASlowScratchServerDoesNotHoldBackTheWindowPastTheBudget() async throws {
        let server = carServer()
        server.delay = .seconds(5)
        let outcome = try await request(trigger: .chain, server: server)
        XCTAssertTrue(outcome.labels.contains("count"), "The regular list is the fallback: \(outcome.labels)")
        XCTAssertLessThan(outcome.elapsed, .milliseconds(1_000), "The window opened after \(outcome.elapsed)")
    }

    func testAcceptingAChainInsertsItInPlaceOfThePrefix() async throws {
        let outcome = try await request(trigger: .chain, server: carServer())
        let entry = try XCTUnwrap(outcome.items.first { $0.label == "car.label" })
        let end = outcome.editor.textView.textStorage.length
        outcome.aggregator.completionWindowApplyCompletion(
            item: entry,
            textView: outcome.editor,
            cursorPosition: CursorPosition(range: NSRange(location: end, length: 0))
        )
        XCTAssertEqual(outcome.editor.text, "void f() {\n    std::string s = car.label")
    }
}
