//
//  CompletionLatencyTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
import CodeEditLanguages
@testable import CodeEditSourceEditor
@testable import CodeEdit

/// The aggregator never lets a slow provider hold the window open longer than its deadline.
@MainActor
final class CompletionLatencyTests: XCTestCase {
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

    // MARK: - Doubles

    /// A provider that answers after `delay`, standing in for a slow language server.
    private final class SlowProvider: CompletionProvider {
        let source: CompletionSource
        let deadline: Duration
        let graceDeadline: Duration
        let delay: Duration
        let labels: [String]

        init(
            source: CompletionSource = .lsp,
            delay: Duration,
            deadline: Duration,
            grace: Duration = .zero,
            labels: [String]
        ) {
            self.source = source
            self.delay = delay
            self.deadline = deadline
            self.graceDeadline = grace
            self.labels = labels
        }

        func candidates(for context: CompletionContext, textView: TextViewController) async -> [CompletionCandidate] {
            try? await Task.sleep(for: delay)
            return labels.map {
                CompletionCandidate(
                    id: "slow.\($0)", label: $0, filterText: $0, kind: .variable, source: source,
                    payload: .plain(insertText: $0)
                )
            }
        }

        func apply(_ candidate: CompletionCandidate, textView: TextViewController, cursorPosition: CursorPosition?) { }
    }

    private final class RecordingMetrics: CompletionMetricsRecording {
        var popups = 0
        var latencies: [CompletionSource] = []
        var acceptances: [(rank: Int, keystrokes: Int)] = []

        func recordPopup() { popups += 1 }
        func recordProviderLatency(source: CompletionSource, duration: Duration) { latencies.append(source) }
        func recordAcceptance(rank: Int, keystrokes: Int) { acceptances.append((rank, keystrokes)) }
    }

    private final class EmptyFrequencyStore: CompletionFrequencyStoring {
        func frequencies(for languageId: String) -> [String: Int] { [:] }
        func recordAcceptance(label: String, languageId: String) { }
    }

    private func makeAggregator(
        source: String,
        providers: [SlowProvider],
        metrics: any CompletionMetricsRecording
    ) throws -> (CompletionAggregator, TextViewController) {
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
            frequencyStore: EmptyFrequencyStore(),
            metrics: metrics,
            additionalProviders: providers
        )
        return (aggregator, editor)
    }

    private func makeAggregator(
        source: String,
        provider: SlowProvider,
        metrics: any CompletionMetricsRecording
    ) throws -> (CompletionAggregator, TextViewController) {
        try makeAggregator(source: source, providers: [provider], metrics: metrics)
    }

    private func request(_ aggregator: CompletionAggregator, in editor: TextViewController) async -> [String]? {
        await aggregator.completionSuggestionsRequested(
            textView: editor,
            cursorPosition: CursorPosition(range: NSRange(location: editor.textView.textStorage.length, length: 0)),
            trigger: .typing
        )?.items.map(\.label)
    }

    // MARK: - Deadlines

    func testLanguageServerProviderHasAnEightHundredMillisecondDeadline() {
        let provider = LSPCompletionProvider(document: CodeFileDocument())
        XCTAssertEqual(provider.deadline, .milliseconds(800))
        XCTAssertLessThanOrEqual(provider.graceDeadline, provider.deadline)
    }

    func testASlowServerDoesNotHoldBackTheWindowWhenLocalCandidatesExist() async throws {
        let provider = SlowProvider(delay: .milliseconds(700), deadline: .milliseconds(800), labels: ["numeric_value"])
        let (aggregator, editor) = try makeAggregator(source: "x = nu", provider: provider, metrics: RecordingMetrics())

        let start = ContinuousClock.now
        let first = await request(aggregator, in: editor)
        let labels = try XCTUnwrap(first)
        XCTAssertLessThan(ContinuousClock.now - start, .milliseconds(400), "The window opens with local candidates")
        XCTAssertTrue(labels.contains("nullptr"))
        XCTAssertFalse(labels.contains("numeric_value"))
    }

    func testALateServerAnswerIsMergedOnTheNextCursorMove() async throws {
        let provider = SlowProvider(delay: .milliseconds(300), deadline: .milliseconds(800), labels: ["numeric_value"])
        let (aggregator, editor) = try makeAggregator(source: "x = nu", provider: provider, metrics: RecordingMetrics())
        _ = await request(aggregator, in: editor)

        var labels: [String] = []
        for _ in 0..<40 where !labels.contains("numeric_value") {
            try await Task.sleep(for: .milliseconds(50))
            labels = aggregator.completionOnCursorMove(
                textView: editor,
                cursorPosition: CursorPosition(range: NSRange(location: editor.textView.textStorage.length, length: 0))
            )?.map(\.label) ?? []
        }
        XCTAssertTrue(labels.contains("numeric_value"), "Got \(labels)")
    }

    func testAGraceDeadlineLetsAFastServerIntoTheFirstList() async throws {
        let provider = SlowProvider(
            delay: .milliseconds(80), deadline: .milliseconds(800), grace: .milliseconds(300), labels: ["numeric_value"]
        )
        let (aggregator, editor) = try makeAggregator(source: "x = nu", provider: provider, metrics: RecordingMetrics())

        let first = await request(aggregator, in: editor)
        let labels = try XCTUnwrap(first)
        XCTAssertTrue(labels.contains("numeric_value"), "Got \(labels)")
        XCTAssertTrue(labels.contains("nullptr"))
    }

    func testTheWindowWaitsForTheDeadlineWhenNothingElseWasOffered() async throws {
        let provider = SlowProvider(delay: .milliseconds(1_500), deadline: .milliseconds(300), labels: ["size"])
        let (aggregator, editor) = try makeAggregator(source: "obj.", provider: provider, metrics: RecordingMetrics())

        let start = ContinuousClock.now
        let labels = await request(aggregator, in: editor)
        let elapsed = ContinuousClock.now - start
        XCTAssertNil(labels, "Nothing to show once the deadline passed")
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(250))
        XCTAssertLessThan(elapsed, .milliseconds(1_000))
    }

    func testAnAnswerWithinTheDeadlineOpensTheWindowWhenNothingElseWasOffered() async throws {
        let provider = SlowProvider(delay: .milliseconds(150), deadline: .milliseconds(800), labels: ["size"])
        let (aggregator, editor) = try makeAggregator(source: "obj.", provider: provider, metrics: RecordingMetrics())

        let labels = await request(aggregator, in: editor)
        XCTAssertEqual(labels, ["size"])
    }

    func testSlowServerAndSlowAIShareOneSecondForTheFirstList() async throws {
        let server = SlowProvider(delay: .milliseconds(1_500), deadline: .milliseconds(800), labels: ["size"])
        let cloud = SlowProvider(
            source: .ai, delay: .milliseconds(1_400), deadline: .milliseconds(2_500), labels: ["data"]
        )
        let (aggregator, editor) = try makeAggregator(
            source: "obj.", providers: [server, cloud], metrics: RecordingMetrics()
        )

        let start = ContinuousClock.now
        let first = await request(aggregator, in: editor)
        let elapsed = ContinuousClock.now - start
        XCTAssertNil(first, "Neither provider answered within the budget")
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(900), "The server was given its deadline")
        XCTAssertLessThan(elapsed, .milliseconds(1_100), "AI was only waited for what remained of one second")

        var labels: [String] = []
        for _ in 0..<40 where !labels.contains("data") {
            try await Task.sleep(for: .milliseconds(50))
            labels = aggregator.completionOnCursorMove(
                textView: editor,
                cursorPosition: CursorPosition(range: NSRange(location: editor.textView.textStorage.length, length: 0))
            )?.map(\.label) ?? []
        }
        XCTAssertTrue(labels.contains("data"), "The late AI answer is merged on a cursor move; got \(labels)")
    }

    // MARK: - Metrics

    func testPopupLatencyAndAcceptanceAreRecorded() async throws {
        let metrics = RecordingMetrics()
        let provider = SlowProvider(delay: .milliseconds(20), deadline: .milliseconds(800), labels: [])
        let (aggregator, editor) = try makeAggregator(source: "x = nu", provider: provider, metrics: metrics)

        let result = await aggregator.completionSuggestionsResult(
            textView: editor,
            cursorPosition: CursorPosition(range: NSRange(location: editor.textView.textStorage.length, length: 0)),
            trigger: .typing
        )
        let items = try XCTUnwrap(result?.items)
        XCTAssertEqual(metrics.popups, 1)
        XCTAssertTrue(metrics.latencies.contains(.lsp))
        XCTAssertTrue(metrics.latencies.contains(.snippet))

        let index = try XCTUnwrap(items.firstIndex { $0.label == "nullptr" })
        aggregator.completionWindowApplyCompletion(
            item: items[index],
            textView: editor,
            cursorPosition: CursorPosition(range: NSRange(location: editor.textView.textStorage.length, length: 0))
        )
        XCTAssertEqual(metrics.acceptances.count, 1)
        XCTAssertEqual(metrics.acceptances.first?.rank, index)
        XCTAssertEqual(metrics.acceptances.first?.keystrokes, 0)
    }
}
