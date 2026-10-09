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

        let syntaxTree = TreeSitterClient()
        let editor = TextViewController(
            string: source,
            language: .cpp,
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

// MARK: - Expected type, postfix and chain

extension ClangdCompletionIntegrationTests {

    /// The rank of the entry labelled `label` (ignoring clangd's leading marker space), or `nil`.
    private func rank(of label: String, in items: [CodeSuggestionEntry]) -> Int? {
        items.firstIndex { $0.label.trimmingCharacters(in: .whitespaces) == label }
    }

    /// Requests completions at the end of `marker` until the server has answered with real symbols,
    /// i.e. until `symbol` is in the list with a type, and returns the result.
    private func completeUntilTyped(
        _ fixture: Fixture,
        after marker: String,
        symbol: String,
        aggregator: CompletionAggregator? = nil
    ) async throws -> CodeSuggestionResult {
        let offset = (fixture.editor.text as NSString).range(of: marker, options: .backwards).max
        fixture.editor.textView.selectionManager.setSelectedRange(NSRange(location: offset, length: 0))
        var last: CodeSuggestionResult?
        for _ in 0..<30 {
            last = await (aggregator ?? fixture.aggregator).completionSuggestionsResult(
                textView: fixture.editor,
                cursorPosition: CursorPosition(range: NSRange(location: offset, length: 0)),
                trigger: .explicit
            )
            if let items = last?.items, let index = rank(of: symbol, in: items), items[index].detail != nil {
                return try XCTUnwrap(last)
            }
            try await Task.sleep(for: .milliseconds(300))
        }
        return try XCTUnwrap(last, "clangd never offered `\(symbol)`")
    }

    /// The expected-type bonus on a real clangd: after `std::string s = ` a `std::string` variable ranks
    /// above an `int` one, and above where it ranks without the expected type.
    func testExpectedTypeLiftsAStringWhereAStringIsDeclared() async throws {
        let source = "#include <string>\nint a_counter;\nstd::string z_label;\n"
            + "int main() {\n    std::string s = \n}\n"
        let fixture = try await makeFixture(source: source)
        let withType = try await completeUntilTyped(fixture, after: "std::string s = ", symbol: "z_label")

        let control = CompletionAggregator(
            document: fixture.document,
            treeSitterClient: TreeSitterClient(),
            frequencyStore: InMemoryCompletionFrequencyStore(),
            metrics: CompletionMetricsStore(fileURL: fixture.directory.appending(path: "control-metrics.json")),
            expectedTypeSource: { _, _ in nil }
        )
        let without = try await completeUntilTyped(
            fixture, after: "std::string s = ", symbol: "z_label", aggregator: control
        )

        let typed = try XCTUnwrap(rank(of: "z_label", in: withType.items), "z_label missing from the typed list")
        let untyped = try XCTUnwrap(rank(of: "z_label", in: without.items), "z_label missing from the control")
        let counter = try XCTUnwrap(rank(of: "a_counter", in: withType.items))
        print("EXPECTED-TYPE z_label rank with=\(typed) without=\(untyped) a_counter with=\(counter)")
        XCTAssertLessThan(typed, counter, "A std::string must rank above an int after `std::string s = `")
        XCTAssertLessThanOrEqual(typed, untyped, "The expected type must not lower the string's rank")

        // clangd already prefers the string here, so the bonus cannot show as a change of rank. Expecting an
        // `int` instead has to turn clangd's order around: the real `detail` of both items is read, and the
        // bonus is strong enough to beat the server's own order.
        let wantsInt = CompletionAggregator(
            document: fixture.document,
            treeSitterClient: TreeSitterClient(),
            frequencyStore: InMemoryCompletionFrequencyStore(),
            metrics: CompletionMetricsStore(fileURL: fixture.directory.appending(path: "int-metrics.json")),
            expectedTypeSource: { _, _ in TypeText.parse("int") }
        )
        let flipped = try await completeUntilTyped(
            fixture, after: "std::string s = ", symbol: "z_label", aggregator: wantsInt
        )
        let flippedCounter = try XCTUnwrap(rank(of: "a_counter", in: flipped.items))
        let flippedLabel = try XCTUnwrap(rank(of: "z_label", in: flipped.items))
        print("EXPECTED-TYPE int expected: a_counter rank=\(flippedCounter) z_label rank=\(flippedLabel)")
        XCTAssertLessThan(flippedCounter, flippedLabel, "The expected-type bonus must be able to reorder clangd's list")
    }

    /// Hover on a real clangd gives the type of the assigned variable.
    func testAssignmentUsesTheTypeOfTheTargetFromHover() async throws {
        let source = "#include <string>\nint a_counter;\nstd::string z_label;\nstd::string target;\n"
            + "int main() {\n    target = \n}\n"
        let fixture = try await makeFixture(source: source)
        let result = try await completeUntilTyped(fixture, after: "target = ", symbol: "z_label")
        let label = try XCTUnwrap(rank(of: "z_label", in: result.items))
        let counter = try XCTUnwrap(rank(of: "a_counter", in: result.items))
        XCTAssertLessThan(label, counter, "Hover says `target` is a std::string")
    }

    /// Signature help on a real clangd gives the type of the parameter the cursor is at.
    func testCallArgumentUsesTheParameterTypeFromSignatureHelp() async throws {
        let source = "#include <string>\nint a_counter;\nstd::string z_label;\n"
            + "void take(int n, const std::string &text);\nint main() {\n    take(1, \n}\n"
        let fixture = try await makeFixture(source: source)
        let result = try await completeUntilTyped(fixture, after: "take(1, ", symbol: "z_label")
        let label = try XCTUnwrap(rank(of: "z_label", in: result.items))
        let counter = try XCTUnwrap(rank(of: "a_counter", in: result.items))
        XCTAssertLessThan(label, counter, "The second parameter of `take` is a std::string")
    }

    /// The postfix `.if` template on a real clangd and a real syntax tree rewrites `flag.if` to an `if`.
    func testPostfixIfRewritesTheExpressionBeforeTheDot() async throws {
        let source = "struct Thing { int size; };\nint main() {\n    bool flag = true;\n    flag.\n}\n"
        let fixture = try await makeFixture(source: source)
        let offset = (fixture.editor.text as NSString).range(of: "flag.\n").location + 5
        // The syntax tree is built asynchronously after the text is set.
        var postfix: CodeSuggestionEntry?
        for _ in 0..<30 where postfix == nil {
            fixture.editor.textView.selectionManager.setSelectedRange(NSRange(location: offset, length: 0))
            let result = await fixture.aggregator.completionSuggestionsResult(
                textView: fixture.editor,
                cursorPosition: CursorPosition(range: NSRange(location: offset, length: 0)),
                trigger: .explicit
            )
            postfix = result?.items.first { $0.label == "if" }
            if postfix == nil { try await Task.sleep(for: .milliseconds(300)) }
        }
        accept(try XCTUnwrap(postfix, "No postfix `if` offered after `flag.`"), at: offset, in: fixture)
        let text = fixture.editor.text
        XCTAssertTrue(text.contains("if (flag) {"), "Missing the rewritten statement in:\n\(text)")
        XCTAssertFalse(text.contains("flag.\n"), "The `flag.` must be replaced in:\n\(text)")
    }
}
