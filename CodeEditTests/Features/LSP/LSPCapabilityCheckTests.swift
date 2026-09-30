//
//  LSPCapabilityCheckTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/30/26.
//

import XCTest
import CodeEditLanguages
import CodeEditSourceEditor
import CodeEditTextView
import LanguageClient
import LanguageServerProtocol
@testable import CodeEdit

/// Requests for features a server did not advertise must not reach the server. `neocmakelsp`, for example,
/// answers `workspace/symbol` with `-32601 Method not found` and provides no semantic tokens.
final class LSPCapabilityCheckTests: XCTestCase {
    final class MockDocumentType: LanguageServerDocument {
        var content: NSTextStorage?
        var languageServerURI: String?
        var languageServerObjects: LanguageServerDocumentObjects<MockDocumentType>

        init() {
            self.content = NSTextStorage(string: "project(demo)\n")
            self.languageServerURI = "file:///test/CMakeLists.txt"
            self.languageServerObjects = .init()
        }

        func getLanguage() -> CodeLanguage {
            .default
        }
    }

    typealias LanguageServerType = LanguageServer<MockDocumentType>

    private var connection: BufferingServerConnection!

    private func makeServer(_ configure: (inout ServerCapabilities) -> Void = { _ in }) async throws
    -> LanguageServerType {
        var capabilities = ServerCapabilities()
        capabilities.textDocumentSync = .optionA(.init(openClose: true, change: .full))
        configure(&capabilities)
        connection = BufferingServerConnection()
        let server = LanguageServerType(
            languageId: "cmake",
            binary: .init(execPath: "", args: [], env: nil),
            lspInstance: InitializingServer(
                server: connection,
                initializeParamsProvider: LanguageServerType.getInitParams(workspacePath: "/")
            ),
            lspPid: -1,
            serverCapabilities: capabilities,
            rootPath: URL(fileURLWithPath: "/"),
            logContainer: LanguageServerLogContainer(languageId: "cmake")
        )
        _ = try await server.lspInstance.initializeIfNeeded()
        return server
    }

    private var sentMethods: [String] {
        connection.clientRequests.map(\.method.rawValue)
    }

    private static let legend = SemanticTokensLegend(tokenTypes: ["keyword"], tokenModifiers: [])

    // MARK: - Workspace Symbols

    func testWorkspaceSymbolSupportFollowsCapabilities() async throws {
        let unsupported = try await makeServer()
        XCTAssertFalse(unsupported.supportsWorkspaceSymbols)

        let disabled = try await makeServer { $0.workspaceSymbolProvider = .optionA(false) }
        XCTAssertFalse(disabled.supportsWorkspaceSymbols)

        let enabled = try await makeServer { $0.workspaceSymbolProvider = .optionA(true) }
        XCTAssertTrue(enabled.supportsWorkspaceSymbols)

        let withOptions = try await makeServer { $0.workspaceSymbolProvider = .optionB(.init()) }
        XCTAssertTrue(withOptions.supportsWorkspaceSymbols)
    }

    func testWorkspaceSymbolRequestIsSkippedWhenUnsupported() async throws {
        let server = try await makeServer()
        let response = try await server.requestWorkspaceSymbols(query: "add_executable")
        XCTAssertNil(response)
        XCTAssertFalse(sentMethods.contains(ClientRequest.Method.workspaceSymbol.rawValue))
    }

    // MARK: - Semantic Tokens

    func testSemanticTokenSupportFollowsCapabilities() async throws {
        let unsupported = try await makeServer()
        XCTAssertFalse(unsupported.supportsSemanticTokens)

        let rangeOnly = try await makeServer {
            $0.semanticTokensProvider = .optionA(.init(legend: Self.legend, range: .optionA(true)))
        }
        XCTAssertFalse(rangeOnly.supportsSemanticTokens)

        let fullOnly = try await makeServer {
            $0.semanticTokensProvider = .optionA(.init(legend: Self.legend, full: .optionA(true)))
        }
        XCTAssertTrue(fullOnly.supportsSemanticTokens)
        XCTAssertFalse(fullOnly.supportsSemanticTokenDeltas)

        let withDeltas = try await makeServer {
            $0.semanticTokensProvider = .optionA(.init(legend: Self.legend, full: .optionB(.init(delta: true))))
        }
        XCTAssertTrue(withDeltas.supportsSemanticTokens)
        XCTAssertTrue(withDeltas.supportsSemanticTokenDeltas)
    }

    func testSemanticTokenRequestIsSkippedWhenUnsupported() async throws {
        let server = try await makeServer()
        let full = try await server.requestSemanticTokens(for: "file:///test/CMakeLists.txt")
        let delta = try await server.requestSemanticTokens(for: "file:///test/CMakeLists.txt", previousResultId: "1")
        XCTAssertNil(full)
        XCTAssertNil(delta)
        XCTAssertFalse(sentMethods.contains { $0.hasPrefix("textDocument/semanticTokens") })
    }

    @MainActor
    func testHighlightProviderFallsBackWhenServerHasNoSemanticTokens() async throws {
        let server = try await makeServer()
        let document = MockDocumentType()
        let provider = document.languageServerObjects.highlightProvider
        let textView = TextView(string: "project(demo)\n")

        // A query made before the server attaches waits for it, then resolves without an error.
        var earlyResult: Result<[HighlightRange], any Error>?
        provider.queryHighlightsFor(textView: textView, range: NSRange(location: 0, length: 7)) { earlyResult = $0 }
        XCTAssertNil(earlyResult)

        try await server.openDocument(document)

        guard case .success(let earlyHighlights) = earlyResult else {
            return XCTFail("Expected an empty success, got \(String(describing: earlyResult))")
        }
        XCTAssertTrue(earlyHighlights.isEmpty)

        var result: Result<[HighlightRange], any Error>?
        provider.queryHighlightsFor(textView: textView, range: NSRange(location: 0, length: 7)) { result = $0 }
        guard case .success(let highlights) = result else {
            return XCTFail("Expected an empty success, got \(String(describing: result))")
        }
        XCTAssertTrue(highlights.isEmpty)

        provider.setUp(textView: textView, codeLanguage: .default)
        try await provider.documentDidChange()
        XCTAssertFalse(sentMethods.contains { $0.hasPrefix("textDocument/semanticTokens") })
    }
}
