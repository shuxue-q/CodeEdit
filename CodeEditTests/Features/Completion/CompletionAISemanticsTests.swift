//
//  CompletionAISemanticsTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
import CodeEditLanguages
@testable import CodeEditSourceEditor
@testable import CodeEdit

/// The aggregator lets providers wait for the semantic facts it resolves, so the AI prompt can carry them.
@MainActor
final class CompletionAISemanticsTests: XCTestCase {
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

    /// Asks the context for its semantic facts, as the AI provider does, and keeps the answer.
    private final class SemanticsSpy: CompletionProvider {
        let source: CompletionSource = .lsp
        let deadline: Duration = .zero
        var budget: Duration = .milliseconds(200)
        var seen: ResolvedSemantics?
        var hadWaiter = false

        func candidates(for context: CompletionContext, textView: TextViewController) async -> [CompletionCandidate] {
            hadWaiter = context.awaitSemantics != nil
            seen = await context.awaitSemantics?(budget)
            return []
        }

        func apply(_ candidate: CompletionCandidate, textView: TextViewController, cursorPosition: CursorPosition?) { }
    }

    private func run(
        spy: SemanticsSpy,
        expected: @escaping (CompletionContext, TextViewController) async -> TypeText?,
        receiver: @escaping (CompletionContext, TextViewController) async -> String?,
        signature: @escaping (CompletionContext, TextViewController) async -> String?
    ) async throws {
        let source = "int f(std::string name) {\n    return na"
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
            additionalProviders: [spy],
            expectedTypeSource: expected,
            receiverTypeSource: receiver,
            functionSignatureSource: signature
        )
        _ = await aggregator.completionSuggestionsResult(
            textView: editor,
            cursorPosition: CursorPosition(range: NSRange(location: editor.textView.textStorage.length, length: 0)),
            trigger: .explicit
        )
    }

    func testProvidersCanReadTheResolvedFacts() async throws {
        let spy = SemanticsSpy()
        try await run(
            spy: spy,
            expected: { _, _ in TypeText.parse("std::string") },
            receiver: { _, _ in "Foo" },
            signature: { _, _ in "int f(std::string name)" }
        )
        XCTAssertTrue(spy.hadWaiter)
        XCTAssertEqual(spy.seen?.expectedType, TypeText.parse("std::string"))
        XCTAssertEqual(spy.seen?.receiverType, "Foo")
        XCTAssertEqual(spy.seen?.functionSignature, "int f(std::string name)")
    }

    func testASlowFactIsLeftOutInsteadOfBlockingTheProvider() async throws {
        let spy = SemanticsSpy()
        spy.budget = .milliseconds(50)
        let start = ContinuousClock.now
        try await run(
            spy: spy,
            expected: { _, _ in
                try? await Task.sleep(for: .seconds(3))
                return TypeText.parse("int")
            },
            receiver: { _, _ in nil },
            signature: { _, _ in "void g()" }
        )
        XCTAssertNil(spy.seen?.expectedType)
        XCTAssertEqual(spy.seen?.functionSignature, "void g()")
        XCTAssertLessThan(ContinuousClock.now - start, .milliseconds(900))
    }
}
