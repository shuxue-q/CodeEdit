//
//  DartIntentTreeTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/13/26.
//

import XCTest
import CodeEditLanguages
import SwiftTreeSitter
@testable import CodeEdit

/// Dart intents in whole documents parsed with the vendored `tree-sitter-dart` grammar, so the node
/// names ``DartKeywords`` relies on are checked against the real parser.
final class DartIntentTreeTests: XCTestCase {
    /// The intent at `|` in `source`, with the node types the vendored Dart grammar reports there,
    /// collected as `TreeSitterClient.nodesAt(location:)` does.
    private func realIntent(_ source: String, line: UInt = #line) throws -> CompletionIntent {
        let cursor = (source as NSString).range(of: "|").location
        let text = source.replacingOccurrences(of: "|", with: "")
        let parser = Parser()
        try parser.setLanguage(try XCTUnwrap(CodeLanguage.dart.language))
        let tree = try XCTUnwrap(parser.parse(text))
        let root = try XCTUnwrap(tree.rootNode, line: line)
        var types: [String] = []
        var node = root.descendant(in: UInt32(2 * cursor)..<UInt32(2 * (cursor + 1)))
        while let current = node {
            if let type = current.nodeType { types.append(type) }
            node = current.parent
        }
        let string = text as NSString
        let lineStart = string.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: cursor))
        let start = lineStart.location == NSNotFound ? 0 : lineStart.location + 1
        let lineText = string.substring(with: NSRange(location: start, length: cursor - start))
        let prefix = String(
            lineText.reversed().prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }.reversed()
        )
        return CompletionIntentRecognizer { _ in types }
            .recognize(at: cursor, prefix: prefix, lineTextBeforeCursor: lineText, languageId: "dart")
    }

    private static let widget = """
    import 'package:flutter/material.dart';

    class Home extends StatelessWidget {
      const Home({super.key});

      @override
      Widget build(BuildContext context) {
        final name = 'Ada';
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Text('Hello $name'),
              CONTENT
            ],
          ),
        );
      }
    }

    """

    private func widget(_ content: String) -> String {
        Self.widget.replacingOccurrences(of: "CONTENT", with: content)
    }

    func testRealTreeInsideAWidgetTree() throws {
        XCTAssertEqual(try realIntent(widget("|")), .expression, "A new element of `children: [`")
        XCTAssertEqual(try realIntent(widget("Te|")), .expression)
        XCTAssertEqual(try realIntent(widget("const Te|")), .typeName)
        XCTAssertEqual(try realIntent(widget("Text(|)")), .argument)
        XCTAssertEqual(try realIntent(widget("Text(name, |)")), .argument)
        XCTAssertEqual(try realIntent(widget("Text(name, sty|)")), .argument)
        XCTAssertEqual(try realIntent(widget("Text(name, style: |)")), .expression)
        XCTAssertEqual(try realIntent(widget("Text(name.|)")), .memberAccess)
        XCTAssertEqual(try realIntent(widget("Text('$na|')")), .variableReference)
        XCTAssertEqual(try realIntent(widget("Text('${na|}')")), .variableReference)
        XCTAssertEqual(try realIntent(widget("Text('plain te|')")), .string)
    }

    func testRealTreeOnANewLineOfAMultiLineArgumentList() throws {
        let source = """
        void main() {
          runApp(Padding(
            padding: EdgeInsets.zero,
            |
          ));
        }
        """
        XCTAssertEqual(try realIntent(source), .argument)
        XCTAssertEqual(try realIntent(source.replacingOccurrences(of: "|", with: "chi|")), .argument)
    }

    func testRealTreeScopes() throws {
        XCTAssertEqual(try realIntent("|"), .topLevel)
        XCTAssertEqual(try realIntent("class A {\n  |\n}\n"), .topLevel)
        XCTAssertEqual(try realIntent("void main() {\n  |\n}\n"), .statement)
        XCTAssertEqual(try realIntent("void main() {\n  f(() {\n    |\n  });\n}\n"), .statement)
        XCTAssertEqual(try realIntent("void f({required int a, |}) {}\n"), .typeName)
        XCTAssertEqual(try realIntent("void main() {\n  // note |\n}\n"), .comment)
        XCTAssertEqual(try realIntent("void main() {\n  final s = '''\nmulti |\n''';\n}\n"), .string)
    }
}
