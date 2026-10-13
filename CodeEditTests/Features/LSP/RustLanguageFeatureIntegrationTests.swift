//
//  RustLanguageFeatureIntegrationTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 10/13/26.
//

import XCTest
@testable import CodeEditSourceEditor
import LanguageServerProtocol
@testable import CodeEdit

/// Hover and `cargo check` diagnostics from rust-analyzer, using ``RustServerFixture``. Skipped when
/// rust-analyzer is not installed.
@MainActor
final class RustLanguageFeatureIntegrationTests: XCTestCase {
    private var fixture: RustServerFixture?

    override func tearDown() async throws {
        fixture?.tearDown()
        fixture = nil
    }

    private static let source = """
    /// Adds one to `x`.
    pub fn add_one(x: u32) -> u32 {
        x + 1
    }

    pub fn use_it() -> u32 {
        add_one(41)
    }

    """

    private func makeFixture() async throws -> RustServerFixture {
        var files = RustCompletionIntegrationTests.workspaceFiles
        files["native/rust/probe/src/lib.rs"] = Self.source
        let made = try await RustServerFixture(files: files, open: "native/rust/probe/src/lib.rs")
        fixture = made
        return made
    }

    func testHoverShowsTheSignatureAndDocumentation() async throws {
        let fixture = try await makeFixture()
        let uri = try XCTUnwrap(fixture.document.languageServerURI)
        var hover: Hover?
        let deadline = ContinuousClock.now + .seconds(180)
        while hover == nil, ContinuousClock.now < deadline {
            hover = try? await fixture.client.requestHover(for: uri, Position(line: 6, character: 6))
            if hover == nil { try await Task.sleep(for: .milliseconds(500)) }
        }
        guard case .optionC(let markup) = try XCTUnwrap(hover, "No hover for add_one").contents else {
            return XCTFail("Expected markup hover contents")
        }
        let documentation = LSPHoverParser.parse(content: markup.value, fallbackLanguage: "rust")
        XCTAssertTrue(
            documentation.declaration?.rawCode.contains("pub fn add_one(x: u32) -> u32") == true,
            "No declaration in \(markup.value)"
        )
        XCTAssertTrue(documentation.summary?.contains("Adds one") == true, "No documentation in \(markup.value)")
    }

    /// `cargo check` runs when the file is saved: CodeEdit sends `textDocument/didSave` for Rust.
    func testSavingRunsCargoCheck() async throws {
        let fixture = try await makeFixture()
        let service = try XCTUnwrap(ServiceContainer.resolve(.singleton, LSPService.self))
        let workspace = fixture.directory.path
        // Wait until the server has loaded the workspace (completion answers), so the save is not lost
        // while it starts.
        _ = try await fixture.complete(after: "    add_one") { items in
            items.contains { $0.label.hasPrefix("add_one") }
        }

        func rustcDiagnostics() -> [Diagnostic] {
            service.diagnosticsStore.diagnostics(for: workspace).values
                .flatMap { $0 }
                .filter { $0.source == "rustc" }
        }
        XCTAssertTrue(rustcDiagnostics().isEmpty, "The clean crate has no cargo check errors")

        let offset = fixture.offset(after: "    add_one(41)")
        fixture.editor.textView.replaceCharacters(
            in: NSRange(location: offset, length: 0),
            with: ";\n    let wrong: u32 = \"text\";\n    0"
        )
        let saved = expectation(description: "saved")
        let url = try XCTUnwrap(fixture.document.fileURL)
        fixture.document.save(to: url, ofType: "public.source-code", for: .saveOperation) { error in
            XCTAssertNil(error)
            saved.fulfill()
        }
        await fulfillment(of: [saved], timeout: 10)

        try await fixture.waitUntil(timeout: .seconds(180)) { !rustcDiagnostics().isEmpty }
        let diagnostics = rustcDiagnostics()
        XCTAssertFalse(diagnostics.isEmpty, "No cargo check diagnostics after saving")
        XCTAssertTrue(
            diagnostics.contains { $0.message.contains("mismatched types") },
            "\(diagnostics.map(\.message))"
        )
    }
}
