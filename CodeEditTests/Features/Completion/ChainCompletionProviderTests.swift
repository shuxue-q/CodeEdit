//
//  ChainCompletionProviderTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
import CodeEditLanguages
@testable import CodeEditSourceEditor
import LanguageServerProtocol
@testable import CodeEdit

@MainActor
final class ChainCompletionProviderTests: XCTestCase {
    // MARK: - Fixtures

    private func firstLevel(
        _ label: String,
        type: String?,
        kind: LSPCompletionCategory = .variable,
        insertText: String? = nil,
        format: InsertTextFormat? = nil
    ) -> CompletionCandidate {
        let item = CompletionItem(
            label: " " + label,
            kind: kind == .function ? .method : .field,
            detail: type,
            insertText: insertText ?? label,
            insertTextFormat: format
        )
        return CompletionCandidate(
            id: "first.\(label)",
            label: label,
            filterText: label,
            kind: kind,
            source: .lsp,
            detail: type,
            payload: .lsp(item)
        )
    }

    private func member(
        _ label: String,
        type: String?,
        kind: CompletionItemKind = .field,
        insertText: String? = nil,
        format: InsertTextFormat? = nil,
        score: Double? = 1
    ) -> (item: CompletionItem, score: Double?) {
        let item = CompletionItem(
            label: " " + label,
            kind: kind,
            detail: type,
            insertText: insertText ?? label,
            insertTextFormat: format
        )
        return (item, score)
    }

    private func context(
        _ source: String = "void f() {\n    Garage g;\n    std::string s = |\n}",
        expected: String? = "std::string"
    ) -> CodeEdit.CompletionContext {
        let cursor = (source as NSString).range(of: "|").location
        let text = source.replacingOccurrences(of: "|", with: "")
        return CodeEdit.CompletionContext(
            prefix: "",
            prefixRange: NSRange(location: cursor, length: 0),
            triggerCharacter: " ",
            intent: .expression,
            languageId: "cpp",
            documentText: text,
            cursorOffset: cursor,
            isExplicit: true,
            expectedType: expected.flatMap(TypeText.parse),
            isChain: true
        )
    }

    private func provider(_ server: FakeChainScratchServer?) -> ChainCompletionProvider {
        ChainCompletionProvider(makeServer: { server })
    }

    private func chains(
        _ provider: ChainCompletionProvider,
        from candidates: [CompletionCandidate],
        context: CodeEdit.CompletionContext? = nil,
        budget: Duration = .seconds(2)
    ) async -> [CompletionCandidate] {
        await provider.chainCandidates(from: candidates, context: context ?? self.context(), budget: budget)
    }

    // MARK: - First-level symbols

    func testFirstLevelSymbolsAreClassTypedVariablesAndParameterlessGetters() {
        let candidates = [
            firstLevel("car", type: "Car"),
            firstLevel("count", type: "int"),
            firstLevel("flag", type: "bool"),
            firstLevel("engine", type: "Engine", kind: .function, insertText: "engine()"),
            firstLevel("lookup", type: "Car", kind: .function, insertText: "lookup(${1:int id})", format: .snippet),
            firstLevel("next", type: "Node *"),
            firstLevel("deep", type: "Node **"),
            firstLevel("~Car", type: nil, kind: .function)
        ]
        let symbols = ChainCompletionProvider.firstLevelSymbols(in: candidates, limit: 8)
        XCTAssertEqual(symbols, [
            .init(expression: "car", accessor: "."),
            .init(expression: "engine()", accessor: "."),
            .init(expression: "next", accessor: "->")
        ])
    }

    func testAtMostEightSymbolsAreChainedThrough() {
        let candidates = (0..<20).map { firstLevel("obj\($0)", type: "Thing") }
        XCTAssertEqual(ChainCompletionProvider.firstLevelSymbols(in: candidates, limit: 8).count, 8)
        XCTAssertEqual(ChainCompletionProvider.maximumFirstLevelSymbols, 8)
    }

    func testOnlyLanguageServerSymbolsAreChainedThrough() {
        var word = firstLevel("car", type: "Car")
        word.source = .word
        XCTAssertTrue(ChainCompletionProvider.firstLevelSymbols(in: [word], limit: 8).isEmpty)
    }

    // MARK: - Chains

    func testMembersOfTheExpectedTypeBecomeChains() async {
        let server = FakeChainScratchServer()
        server.membersAfter["car."] = [
            member("label", type: "std::string"),
            member("doors", type: "int"),
            member("engine", type: "Engine"),
            member("name", type: "basic_string<char>", kind: .method, insertText: "name()")
        ]
        let result = await chains(provider(server), from: [firstLevel("car", type: "Car")])
        XCTAssertEqual(result.map(\.label), ["car.label", "car.name"])
        XCTAssertEqual(result.first?.detail, "std::string")
        guard case .plain(let text) = result.first?.payload else { return XCTFail("Expected plain text") }
        XCTAssertEqual(text, "car.label")
        guard case .plain(let call) = result.last?.payload else { return XCTFail("Expected plain text") }
        XCTAssertEqual(call, "car.name()")
    }

    func testConvertibleMembersAreChainsToo() async {
        let server = FakeChainScratchServer()
        server.membersAfter["car."] = [member("doors", type: "int"), member("label", type: "std::string")]
        let result = await chains(
            provider(server),
            from: [firstLevel("car", type: "Car")],
            context: context(expected: "long")
        )
        XCTAssertEqual(result.map(\.label), ["car.doors"])
    }

    func testPointersAreFollowedWithAnArrow() async {
        let server = FakeChainScratchServer()
        server.membersAfter["head->"] = [member("name", type: "std::string")]
        let result = await chains(provider(server), from: [firstLevel("head", type: "Node *")])
        XCTAssertEqual(result.map(\.label), ["head->name"])
    }

    func testFunctionMembersWithParametersInsertASnippet() async {
        let server = FakeChainScratchServer()
        server.membersAfter["car."] = [
            member(
                "describe",
                type: "std::string",
                kind: .method,
                insertText: "describe(${1:int verbosity})",
                format: .snippet
            )
        ]
        let result = await chains(provider(server), from: [firstLevel("car", type: "Car")])
        guard case .snippet(let body) = result.first?.payload else { return XCTFail("Expected a snippet") }
        XCTAssertEqual(body, "car.describe(${1:int verbosity})")
    }

    func testDestructorsAndOperatorsAreNotChains() async {
        let server = FakeChainScratchServer()
        server.membersAfter["car."] = [
            member("~Car", type: "std::string", kind: .method),
            member("operator=", type: "std::string", kind: .method)
        ]
        let result = await chains(provider(server), from: [firstLevel("car", type: "Car")])
        XCTAssertTrue(result.isEmpty)
    }

    func testTheScratchDocumentReplacesThePrefixAndTheUsersTextIsUntouched() async {
        let server = FakeChainScratchServer()
        server.membersAfter["car."] = [member("label", type: "std::string")]
        let source = "void f() {\n    std::string s = la|\n}"
        var request = context(source)
        request.prefix = "la"
        request.prefixRange = NSRange(location: request.cursorOffset - 2, length: 2)
        let original = request.documentText
        _ = await chains(provider(server), from: [firstLevel("car", type: "Car")], context: request)

        XCTAssertEqual(server.updates, ["void f() {\n    std::string s = car.\n}"])
        XCTAssertEqual(server.positions, [Position(line: 1, character: 24)])
        XCTAssertEqual(request.documentText, original)
    }

    func testEachSymbolIsAskedAboutInTurn() async {
        let server = FakeChainScratchServer()
        server.membersAfter["a."] = [member("label", type: "std::string")]
        server.membersAfter["b."] = [member("title", type: "std::string")]
        let result = await chains(
            provider(server),
            from: [firstLevel("a", type: "A"), firstLevel("b", type: "B")]
        )
        XCTAssertEqual(result.map(\.label), ["a.label", "b.title"])
        XCTAssertEqual(server.updates.count, 2)
    }

    // MARK: - Nothing to offer

    func testNothingWithoutAnExpectedType() async {
        let server = FakeChainScratchServer()
        server.membersAfter["car."] = [member("label", type: "std::string")]
        let result = await chains(
            provider(server),
            from: [firstLevel("car", type: "Car")],
            context: context(expected: nil)
        )
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(server.updates.isEmpty, "No type to match: the server must not be asked")
    }

    func testNothingWithoutALanguageServer() async {
        let result = await chains(provider(nil), from: [firstLevel("car", type: "Car")])
        XCTAssertTrue(result.isEmpty)
    }

    func testAServerThatRefusesTheScratchDocumentYieldsNothing() async {
        let server = FakeChainScratchServer()
        server.failure = NSError(domain: "clangd", code: -32001)
        let result = await chains(provider(server), from: [firstLevel("car", type: "Car")])
        XCTAssertTrue(result.isEmpty)
    }

    func testNothingWithoutAnyChainableSymbol() async {
        let server = FakeChainScratchServer()
        let result = await chains(provider(server), from: [firstLevel("count", type: "int")])
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(server.updates.isEmpty)
    }

    // MARK: - Budget

    func testASlowServerReturnsTheChainsFoundInTimeWithinTheBudget() async {
        let server = FakeChainScratchServer()
        server.membersAfter["a."] = [member("label", type: "std::string")]
        server.membersAfter["b."] = [member("title", type: "std::string")]
        let slow = SlowAfterFirstScratchServer(server: server)
        let provider = ChainCompletionProvider(makeServer: { slow })
        let start = ContinuousClock.now
        let result = await provider.chainCandidates(
            from: [firstLevel("a", type: "A"), firstLevel("b", type: "B")],
            context: context(),
            budget: .milliseconds(300)
        )
        XCTAssertEqual(result.map(\.label), ["a.label"], "The chain found before the budget ran out is kept")
        XCTAssertLessThan(ContinuousClock.now - start, .milliseconds(800))
    }

    func testAnExhaustedBudgetOffersNothing() async {
        let server = FakeChainScratchServer()
        let result = await chains(provider(server), from: [firstLevel("car", type: "Car")], budget: .zero)
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(server.updates.isEmpty)
    }

    func testShutdownClosesTheScratchDocument() async throws {
        let server = FakeChainScratchServer()
        server.membersAfter["car."] = [member("label", type: "std::string")]
        let provider = provider(server)
        _ = await chains(provider, from: [firstLevel("car", type: "Car")])
        provider.shutdown()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(server.closeCount, 1)
    }

    // MARK: - Helpers

    func testPositionsAreZeroBasedLineAndColumn() {
        let text = "ab\ncde\n\nf" as NSString
        XCTAssertEqual(ChainCompletionProvider.position(of: 0, in: text), Position(line: 0, character: 0))
        XCTAssertEqual(ChainCompletionProvider.position(of: 4, in: text), Position(line: 1, character: 1))
        XCTAssertEqual(ChainCompletionProvider.position(of: 7, in: text), Position(line: 2, character: 0))
        XCTAssertEqual(ChainCompletionProvider.position(of: 9, in: text), Position(line: 3, character: 1))
        XCTAssertNil(ChainCompletionProvider.position(of: 10, in: text))
    }

    func testScratchDocumentsAreRecognizedByTheirName() {
        XCTAssertTrue(LSPChainScratchServer.isScratchURI("file:///src/\(LSPChainScratchServer.namePrefix)ab12cd34.cpp"))
        XCTAssertFalse(LSPChainScratchServer.isScratchURI("file:///src/main.cpp"))
    }
}
