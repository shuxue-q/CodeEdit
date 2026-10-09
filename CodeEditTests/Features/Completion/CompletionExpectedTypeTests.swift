//
//  CompletionExpectedTypeTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
import CodeEditLanguages
@testable import CodeEditSourceEditor
@testable import CodeEdit

/// The aggregator hands the slot's expected type to the ranker, within the latency budget.
@MainActor
final class CompletionExpectedTypeTests: XCTestCase {
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

    /// A language server stand-in offering a `count` of type `int` and a `name` of type `std::string`,
    /// in that order.
    private final class TypedProvider: CompletionProvider {
        let source: CompletionSource = .lsp
        let deadline: Duration = .zero

        func candidates(for context: CompletionContext, textView: TextViewController) async -> [CompletionCandidate] {
            [("count", "int"), ("name", "std::string")].map { label, detail in
                CompletionCandidate(
                    id: "typed.\(label)", label: label, filterText: label, sortText: label, kind: .variable,
                    source: .lsp, detail: detail, payload: .plain(insertText: label)
                )
            }
        }

        func apply(_ candidate: CompletionCandidate, textView: TextViewController, cursorPosition: CursorPosition?) { }
    }

    private func labels(
        source: String,
        expectedType: @escaping (CompletionContext, TextViewController) async -> TypeText?
    ) async throws -> (labels: [String], elapsed: Duration) {
        let file = directory.appending(path: "main.cpp")
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
            additionalProviders: [TypedProvider()],
            expectedTypeSource: expectedType
        )
        let start = ContinuousClock.now
        let result = await aggregator.completionSuggestionsResult(
            textView: editor,
            cursorPosition: CursorPosition(range: NSRange(location: editor.textView.textStorage.length, length: 0)),
            trigger: .explicit
        )
        return (result?.items.map(\.label) ?? [], ContinuousClock.now - start)
    }

    func testTheExpectedTypeReachesTheRanker() async throws {
        let (withType, _) = try await labels(source: "std::string s = ") { _, _ in TypeText.parse("std::string") }
        XCTAssertEqual(withType.first, "name", "Got \(withType)")
        let (without, _) = try await labels(source: "std::string s = ") { _, _ in nil }
        XCTAssertEqual(without.first, "count", "Got \(without)")
    }

    func testTheContextCarriesTheCursorAndPrefixToTheSource() async throws {
        var seen: CompletionContext?
        _ = try await labels(source: "x = fo") { context, _ in
            seen = context
            return nil
        }
        XCTAssertEqual(seen?.prefix, "fo")
        XCTAssertEqual(seen?.cursorOffset, 6)
        XCTAssertEqual(seen?.intent, .expression)
    }

    func testASlowExpectedTypeDoesNotHoldBackThePopup() async throws {
        let (slow, elapsed) = try await labels(source: "std::string s = ") { _, _ in
            try? await Task.sleep(for: .seconds(3))
            return TypeText.parse("std::string")
        }
        XCTAssertEqual(slow.first, "count", "A type that arrives too late must not reorder the list: \(slow)")
        XCTAssertLessThan(elapsed, .milliseconds(700), "The popup waited \(elapsed) for the expected type")
    }
}
