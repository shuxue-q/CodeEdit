//
//  DartLanguageFeatureIntegrationTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 10/13/26.
//

import XCTest
@testable import CodeEditSourceEditor
import LanguageServerProtocol
@testable import CodeEdit

/// Diagnostics, hover and semantic tokens from the Dart analysis server, using ``DartServerFixture``.
/// Skipped when no Dart SDK is found.
@MainActor
final class DartLanguageFeatureIntegrationTests: XCTestCase {
    private var fixture: DartServerFixture?

    override func tearDown() async throws {
        fixture?.tearDown()
        fixture = nil
    }

    private func makeFixture(files: [String: String], open: String) async throws -> DartServerFixture {
        let made = try await DartServerFixture(files: files, open: open)
        fixture = made
        return made
    }

    func testOnlyTheOpenFileGetsDiagnostics() async throws {
        let fixture = try await makeFixture(
            files: [
                "lib/open.dart": "void a() { int x = 'text'; }\n",
                "lib/closed.dart": "void b() { int y = 'text'; }\n",
                "other/pubspec.yaml": "name: other\nenvironment:\n  sdk: ^3.0.0\n",
                "other/lib/elsewhere.dart": "void c() { int z = 'text'; }\n"
            ],
            open: "lib/open.dart"
        )
        let service = try XCTUnwrap(ServiceContainer.resolve(.singleton, LSPService.self))
        let workspace = fixture.directory.path
        try await fixture.waitUntil(timeout: .seconds(20)) {
            !service.diagnosticsStore.diagnostics(for: workspace).isEmpty
        }
        // Give the server time to publish for the closed files, if it were going to.
        try await Task.sleep(for: .seconds(3))

        let uris = service.diagnosticsStore.diagnostics(for: workspace).keys.map { $0.lowercased() }
        XCTAssertEqual(uris.count, 1, "Diagnostics for \(uris)")
        XCTAssertTrue(uris.first?.hasSuffix("/lib/open.dart") == true, "Diagnostics for \(uris)")
    }

    func testHoverShowsTheDeclarationAndDocumentation() async throws {
        let fixture = try await makeFixture(
            files: ["lib/main.dart": "void main() {\n  print('hello');\n}\n"],
            open: "lib/main.dart"
        )
        let uri = try XCTUnwrap(fixture.document.languageServerURI)
        var hover: Hover?
        for _ in 0..<40 where hover == nil {
            hover = try? await fixture.client.requestHover(for: uri, Position(line: 1, character: 3))
            if hover == nil { try await Task.sleep(for: .milliseconds(300)) }
        }
        guard case .optionC(let markup) = try XCTUnwrap(hover, "No hover for print").contents else {
            return XCTFail("Expected markup hover contents")
        }
        let documentation = LSPHoverParser.parse(content: markup.value, fallbackLanguage: "dart")
        XCTAssertTrue(documentation.declaration?.code.contains("print") == true, "No declaration in \(markup.value)")
        XCTAssertFalse((documentation.summary ?? "").isEmpty, "No documentation in \(markup.value)")
    }

    func testSemanticTokensWithoutDeltaSupportDecodeToCaptures() async throws {
        let source = """
        class Counter {
          int count = 0;
          void increment(int by) { count += by; }
        }

        void main() {
          final counter = Counter();
          counter.increment(2);
        }

        """
        let fixture = try await makeFixture(files: ["lib/main.dart": source], open: "lib/main.dart")
        let client = fixture.client
        XCTAssertTrue(client.supportsSemanticTokens)
        XCTAssertFalse(client.supportsSemanticTokenDeltas, "Dart serves full tokens only")
        let map = try XCTUnwrap(client.highlightMap)
        let uri = try XCTUnwrap(fixture.document.languageServerURI)

        var captures: Set<CaptureName> = []
        for _ in 0..<40 where !captures.contains(.method) {
            if let tokens = try? await client.requestSemanticTokens(for: uri) {
                captures = Set(map.decode(tokens: tokens, using: fixture.editor.textView).compactMap(\.capture))
            }
            if !captures.contains(.method) { try await Task.sleep(for: .milliseconds(300)) }
        }
        XCTAssertTrue(
            captures.isSuperset(of: [.type, .method, .parameter, .property, .variable]),
            "Captures: \(captures.map(\.stringValue).sorted())"
        )

        // A delta request to a server without delta support falls back to a full response.
        let delta = try await client.requestSemanticTokens(for: uri, previousResultId: "1")
        guard case .optionA = try XCTUnwrap(delta) else {
            return XCTFail("Expected a full token response")
        }
    }
}
