//
//  CompletionAggregatorTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/29/26.
//

import XCTest
import CodeEditLanguages
@testable import CodeEditSourceEditor
@testable import CodeEdit

@MainActor
final class CompletionAggregatorTests: XCTestCase {
    private var directory: URL!
    /// The aggregator holds its document weakly; keep it alive for the test.
    private var document: CodeFileDocument?

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        document = nil
        try? FileManager.default.removeItem(at: directory)
    }

    /// Typing the second `:` of `::` must drop the candidates requested at the first `:`, so the
    /// window closes and the trigger re-requests at the real completion site.
    func testSecondColonOfScopeOperatorDiscardsStaleCandidates() async throws {
        let (aggregator, editor) = try makeAggregator(source: "template <typename T> std:")
        let requestOffset = editor.textView.textStorage.length

        let initial = await aggregator.completionSuggestionsRequested(
            textView: editor,
            cursorPosition: CursorPosition(range: NSRange(location: requestOffset, length: 0))
        )
        XCTAssertFalse(try XCTUnwrap(initial).items.isEmpty, "Keywords are offered after a single `:`")

        editor.textView.replaceCharacters(in: NSRange(location: requestOffset, length: 0), with: ":")
        let moved = aggregator.completionOnCursorMove(
            textView: editor,
            cursorPosition: CursorPosition(range: NSRange(location: requestOffset + 1, length: 0))
        )
        XCTAssertNil(moved, "Candidates from `std:` must not be shown after `std::`")
    }

    /// A fresh request after `::` must not include the static C++ keywords.
    func testRequestAfterScopeOperatorExcludesKeywords() async throws {
        let (aggregator, editor) = try makeAggregator(source: "template <typename T> std::")
        let result = await aggregator.completionSuggestionsRequested(
            textView: editor,
            cursorPosition: CursorPosition(range: NSRange(location: editor.textView.textStorage.length, length: 0))
        )
        let labels = result?.items.map(\.label) ?? []
        XCTAssertFalse(labels.contains("template"), "Unexpected keywords after `std::`: \(labels)")
    }

    /// Word characters typed after the request keep filtering the cached candidates.
    func testTypingWordCharactersKeepsFilteringCachedCandidates() async throws {
        let (aggregator, editor) = try makeAggregator(source: "t")
        _ = await aggregator.completionSuggestionsRequested(
            textView: editor,
            cursorPosition: CursorPosition(range: NSRange(location: 1, length: 0))
        )

        editor.textView.replaceCharacters(in: NSRange(location: 1, length: 0), with: "em")
        let moved = aggregator.completionOnCursorMove(
            textView: editor,
            cursorPosition: CursorPosition(range: NSRange(location: 3, length: 0))
        )
        XCTAssertEqual(moved?.first?.label, "template")
    }

    private func makeAggregator(source: String) throws -> (CompletionAggregator, TextViewController) {
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
            frequencyStore: EmptyFrequencyStore()
        )
        return (aggregator, editor)
    }
}

private final class EmptyFrequencyStore: CompletionFrequencyStoring {
    func frequencies(for languageId: String) -> [String: Int] { [:] }
    func recordAcceptance(label: String, languageId: String) { }
}
