//
//  DartCompletionIntentIntegrationTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/13/26.
//

import XCTest
import CodeEditLanguages
@testable import CodeEditSourceEditor
import LanguageServerProtocol
@testable import CodeEdit

/// Dart completion intent with the Dart analysis server: named arguments after `(` and `,`, values after a
/// named argument's `:`, variables after `$` in a string, no popup in a plain string, and re-requesting a
/// capped (incomplete) list as the prefix grows.
///
/// Skipped when no Dart SDK is found; the Flutter case also needs `TEST_RUNNER_DART_FLUTTER_PROJECT` (see
/// ``DartCompletionIntegrationTests``).
@MainActor
final class DartCompletionIntentIntegrationTests: XCTestCase {
    private var fixture: DartServerFixture?

    override func tearDown() async throws {
        fixture?.tearDown()
        fixture = nil
    }

    private func makeFixture(
        files: [String: String],
        open: String,
        packageConfig: Data? = nil
    ) async throws -> DartServerFixture {
        let made = try await DartServerFixture(files: files, open: open, packageConfig: packageConfig)
        fixture = made
        return made
    }

    private static func isNamedArgument(_ entry: CodeSuggestionEntry) -> Bool {
        CompletionIntentPolicy.isNamedArgumentLabel(entry.label)
    }

    func testInterpolationOffersVariables() async throws {
        let fixture = try await makeFixture(
            files: ["lib/main.dart": """
            void main() {
              final userName = 'Ada';
              final count = 3;
              print('Hi $us');
              print('Total ${co}');
            }

            """],
            open: "lib/main.dart"
        )
        let (offset, result) = try await fixture.complete(after: "'Hi $us") { items in
            items.contains { $0.label == "userName" }
        }
        let items = try XCTUnwrap(result?.items, "Nothing offered after `'Hi $us`")
        XCTAssertEqual(items.first?.label, "userName", "\(items.prefix(10).map(\.label))")
        fixture.accept(try XCTUnwrap(items.first), at: offset)
        try await fixture.waitForText(containing: "print('Hi $userName');")
        XCTAssertTrue(fixture.editor.text.contains("print('Hi $userName');"), "Got:\n\(fixture.editor.text)")

        let (_, braced) = try await fixture.complete(after: "${co") { items in
            items.contains { $0.label == "count" }
        }
        XCTAssertEqual(braced?.items.first?.label, "count", "\(braced?.items.prefix(10).map(\.label) ?? [])")
    }

    func testTypingInAPlainStringDoesNotOpenTheWindow() async throws {
        let fixture = try await makeFixture(
            files: ["lib/main.dart": "void main() {\n  print('hello wo');\n}\n"],
            open: "lib/main.dart"
        )
        let offset = fixture.offset(after: "hello wo")
        let result = await fixture.aggregator.completionSuggestionsResult(
            textView: fixture.editor,
            cursorPosition: CursorPosition(range: NSRange(location: offset, length: 0)),
            trigger: .typing
        )
        XCTAssertNil(result, "A popup opened inside a plain string: \(result?.items.prefix(5).map(\.label) ?? [])")
    }

    /// The Dart server marks a list incomplete when it hits the item cap (500, see
    /// `LanguageServerConfiguration`), as it does for an empty prefix at statement start. Typing more asks it
    /// again with the longer prefix, and the server's candidates in the open list are replaced by the new answer.
    func testIncompleteListIsAskedAgainAsThePrefixGrows() async throws {
        let fixture = try await makeFixture(
            files: ["lib/main.dart": "void main() {\n  final duration = 1;\n  \n}\n"],
            open: "lib/main.dart"
        )
        let (offset, result) = try await fixture.complete(after: "= 1;\n  ") { items in
            items.contains { ($0 as? AggregatedCompletionEntry)?.candidate.source == .lsp }
        }
        XCTAssertNotNil(result)
        let aggregator = fixture.aggregator
        XCTAssertTrue(aggregator.serverList.isIncomplete, "The Dart server's list was not marked incomplete")
        let firstIDs = Set(aggregator.rawCandidates.filter { $0.source == .lsp }.map(\.id))

        let (typedOffset, _) = fixture.type("dur", at: offset)
        XCTAssertEqual(aggregator.serverList.requestPrefix, "dur")
        try await fixture.waitUntil(timeout: .seconds(5)) {
            aggregator.lspProvider.requestOffset == typedOffset
        }
        XCTAssertEqual(aggregator.lspProvider.requestOffset, typedOffset, "The server was not asked again")
        let newIDs = Set(aggregator.rawCandidates.filter { $0.source == .lsp }.map(\.id))
        XCTAssertFalse(newIDs.isEmpty)
        XCTAssertTrue(newIDs.isDisjoint(with: firstIDs), "The first answer's server items were not replaced")

        let update = aggregator.completionSuggestionsUpdated(
            textView: fixture.editor,
            cursorPosition: CursorPosition(range: NSRange(location: typedOffset, length: 0))
        )
        XCTAssertEqual(update?.items.first?.label, "duration", "\(update?.items.prefix(5).map(\.label) ?? [])")

        // Deleting back past the prefix the server was last asked with asks it again, even when that answer
        // was complete: a complete list is only good for prefixes that extend its own.
        let shorter = typedOffset - 1
        fixture.editor.textView.replaceCharacters(in: NSRange(location: shorter, length: 1), with: "")
        fixture.editor.textView.selectionManager.setSelectedRange(NSRange(location: shorter, length: 0))
        _ = aggregator.completionSuggestionsUpdated(
            textView: fixture.editor,
            cursorPosition: CursorPosition(range: NSRange(location: shorter, length: 0))
        )
        XCTAssertEqual(aggregator.serverList.requestPrefix, "du")
        try await fixture.waitUntil(timeout: .seconds(5)) {
            aggregator.lspProvider.requestOffset == shorter
        }
        XCTAssertEqual(aggregator.lspProvider.requestOffset, shorter, "The server was not asked again for `du`")
    }

    // MARK: - Flutter

    private static let widgetTreeSource = """
    import 'package:flutter/material.dart';

    Widget first() {
      return Padding();
    }

    Widget second() => Padding(padding: EdgeInsets.all(1), );

    Widget third() => Padding(padding: EdgeInsets.zero, child: );

    """

    func testFlutterNamedArgumentsLeadAndValuesFollow() async throws {
        let fixture = try await makeFixture(
            files: ["lib/tree.dart": Self.widgetTreeSource],
            open: "lib/tree.dart",
            packageConfig: try DartServerFixture.flutterPackageConfig()
        )

        // Wait for the server's `padding: `, not the document word `padding`.
        let (_, opening) = try await fixture.complete(after: "return Padding(") { items in
            items.contains { $0.label.hasPrefix("padding:") }
        }
        let afterParen = try XCTUnwrap(opening?.items)
        let parenLabels = afterParen.prefix(10).map(\.label)
        XCTAssertTrue(Self.isNamedArgument(try XCTUnwrap(afterParen.first)), "After `(`: \(parenLabels)")
        XCTAssertTrue(
            afterParen.prefix(3).contains { $0.label.hasPrefix("padding:") },
            "`padding:` should lead after `Padding(`: \(parenLabels)"
        )

        let (_, comma) = try await fixture.complete(after: "EdgeInsets.all(1), ") { items in
            items.contains { $0.label.hasPrefix("child:") }
        }
        let afterComma = try XCTUnwrap(comma?.items)
        let commaLabels = afterComma.prefix(10).map(\.label)
        XCTAssertTrue(Self.isNamedArgument(try XCTUnwrap(afterComma.first)), "After `,`: \(commaLabels)")
        XCTAssertTrue(afterComma.prefix(3).contains { $0.label.hasPrefix("child:") }, "After `,`: \(commaLabels)")

        let (_, value) = try await fixture.complete(after: "child: ") { items in
            items.contains { $0.label.hasPrefix("Text") }
        }
        let afterColon = try XCTUnwrap(value?.items)
        let colonLabels = afterColon.prefix(10).map(\.label)
        XCTAssertFalse(afterColon.prefix(10).contains(where: Self.isNamedArgument), "After `child: `: \(colonLabels)")
        XCTAssertTrue(
            afterColon.contains { $0.label.hasPrefix("Text") },
            "No widget offered after `child: `: \(colonLabels)"
        )
    }
}
