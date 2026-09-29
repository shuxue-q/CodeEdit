//
//  LSPCompletionOriginTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/27/26.
//

import XCTest
import LanguageServerProtocol
@testable import CodeEdit
@testable import CodeEditSourceEditor

final class LSPCompletionOriginTests: XCTestCase {
    func testQualifiedNameStripsClangdIncludeMarker() {
        XCTAssertEqual(
            LSPCompletionOrigin.qualifiedName(from: " CLI::adl_detail"),
            LSPCompletionOrigin.QualifiedName(qualifier: "CLI", name: "adl_detail")
        )
        XCTAssertEqual(
            LSPCompletionOrigin.qualifiedName(from: "•std::add_const"),
            LSPCompletionOrigin.QualifiedName(qualifier: "std", name: "add_const")
        )
    }

    func testHeaderSpellingUsesTheIncludeDirectory() {
        let url = URL(fileURLWithPath: "/Users/ronnie/Desktop/AVX/third_party/CLI11/include/CLI/CLI.hpp")
        XCTAssertEqual(LSPCompletionOrigin.headerSpelling(for: url), "<CLI/CLI.hpp>")
        let local = URL(fileURLWithPath: "/tmp/project/src/Widget.h")
        XCTAssertEqual(LSPCompletionOrigin.headerSpelling(for: local), "Widget.h")
    }

    func testMatchPicksTheContainerAndIgnoresAmbiguousNames() {
        let cli = URL(fileURLWithPath: "/opt/include/CLI/CLI.hpp")
        let other = URL(fileURLWithPath: "/opt/include/other/adl_detail.hpp")
        let symbols = [
            LSPCompletionOrigin.Hit(name: "adl_detail", containerName: "CLI", uri: cli.absoluteString),
            LSPCompletionOrigin.Hit(name: "adl_detail", containerName: "other", uri: other.absoluteString)
        ]
        XCTAssertEqual(
            LSPCompletionOrigin.match(label: " CLI::adl_detail", symbols: symbols)?.path,
            cli.path
        )
        XCTAssertNil(LSPCompletionOrigin.match(label: " adl_detail", symbols: symbols))
    }

    func testDeclaringHeaderFromSymbolInformation() {
        let url = URL(fileURLWithPath: "/opt/include/CLI/CLI.hpp")
        let info = SymbolInformation(
            name: "adl_detail",
            kind: .namespace,
            location: Location(
                uri: url.absoluteString,
                range: LSPRange(start: Position((1635, 10)), end: Position((1635, 20)))
            ),
            containerName: "CLI"
        )
        let header = LSPCompletionOrigin.declaringHeader(for: " CLI::adl_detail", response: .optionA([info]))
        XCTAssertEqual(header, "<CLI/CLI.hpp>")
    }

    func testOriginHeaderIsReadableByTheSuggestionWindow() {
        let entry = LSPCompletionEntry(
            item: CompletionItem(label: " CLI::adl_detail", kind: .module)
        )
        let updated = entry.withOriginHeader("<CLI/CLI.hpp>")
        XCTAssertEqual(SuggestionOrigin.header(in: updated.documentation), "<CLI/CLI.hpp>")
        XCTAssertFalse(LSPCompletionOrigin.hasHeader(documentation: entry.documentation, detail: entry.detail))
        XCTAssertTrue(LSPCompletionOrigin.hasHeader(documentation: updated.documentation, detail: nil))
    }
}
