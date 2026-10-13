//
//  RustIntentTreeTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/13/26.
//

import XCTest
import CodeEditLanguages
import SwiftTreeSitter
@testable import CodeEdit

/// Rust intents in whole documents parsed with the vendored `tree-sitter-rust` grammar, so the node names
/// ``RustKeywords`` relies on are checked against the real parser.
final class RustIntentTreeTests: XCTestCase {
    /// A parsed source: the node types at the cursor, the text without `|`, and the cursor offset.
    private struct Parsed {
        let types: [String]
        let text: String
        let cursor: Int
    }

    /// The node types at `|` in `source`, innermost first, collected as `TreeSitterClient.nodesAt(location:)`
    /// does.
    private func nodeTypes(_ source: String, line: UInt = #line) throws -> Parsed {
        let cursor = (source as NSString).range(of: "|").location
        let text = source.replacingOccurrences(of: "|", with: "")
        let parser = Parser()
        try parser.setLanguage(try XCTUnwrap(CodeLanguage.rust.language))
        let tree = try XCTUnwrap(parser.parse(text))
        let root = try XCTUnwrap(tree.rootNode, line: line)
        var types: [String] = []
        var node = root.descendant(in: UInt32(2 * cursor)..<UInt32(2 * (cursor + 1)))
        while let current = node {
            if let type = current.nodeType { types.append(type) }
            node = current.parent
        }
        return Parsed(types: types, text: text, cursor: cursor)
    }

    /// The intent at `|` in `source`.
    private func realIntent(_ source: String, line: UInt = #line) throws -> CompletionIntent {
        let parsed = try nodeTypes(source, line: line)
        let (types, text, cursor) = (parsed.types, parsed.text, parsed.cursor)
        let string = text as NSString
        let lineStart = string.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: cursor))
        let start = lineStart.location == NSNotFound ? 0 : lineStart.location + 1
        let lineText = string.substring(with: NSRange(location: start, length: cursor - start))
        let prefix = String(lineText.reversed().prefix { $0.isLetter || $0.isNumber || $0 == "_" }.reversed())
        return CompletionIntentRecognizer { _ in types }
            .recognize(at: cursor, prefix: prefix, lineTextBeforeCursor: lineText, languageId: "rust")
    }

    private static let source = """
    use std::collections::HashMap;

    /// A counter.
    pub struct Counter {
        count: u32,
        CONTENT_STRUCT
    }

    pub enum Mode {
        Fast,
        CONTENT_ENUM
    }

    impl Counter {
        CONTENT_IMPL

        pub fn bump(&mut self, by: u32) -> u32 {
            let total = self.count + by;
            CONTENT_BODY
            total
        }
    }

    CONTENT_FILE

    """

    private func source(
        file: String = "",
        impl: String = "",
        body: String = "",
        structBody: String = "",
        enumBody: String = ""
    ) -> String {
        Self.source
            .replacingOccurrences(of: "CONTENT_FILE", with: file)
            .replacingOccurrences(of: "CONTENT_IMPL", with: impl)
            .replacingOccurrences(of: "CONTENT_BODY", with: body)
            .replacingOccurrences(of: "CONTENT_STRUCT", with: structBody)
            .replacingOccurrences(of: "CONTENT_ENUM", with: enumBody)
    }

    func testScopesFromTheRealTree() throws {
        XCTAssertEqual(try realIntent(source(body: "|")), .statement, "A function body")
        XCTAssertEqual(try realIntent(source(body: "pri|")), .statement)
        XCTAssertEqual(try realIntent(source(impl: "|")), .topLevel, "An impl body")
        XCTAssertEqual(try realIntent(source(impl: "pu|")), .topLevel)
        XCTAssertEqual(try realIntent(source(file: "|")), .topLevel, "File scope")
        XCTAssertEqual(try realIntent(source(file: "st|")), .topLevel)
        XCTAssertEqual(try realIntent(source(structBody: "na|")), .declarationName, "A struct body")
        XCTAssertEqual(try realIntent(source(enumBody: "Sl|")), .declarationName, "An enum body")
    }

    func testLineRulesInsideTheRealTree() throws {
        XCTAssertEqual(try realIntent(source(body: "self.|")), .memberAccess)
        XCTAssertEqual(try realIntent(source(body: "let m = std::|")), .scopeAccess)
        XCTAssertEqual(try realIntent(source(body: "let m: HashMap<String, |")), .typeName)
        XCTAssertEqual(try realIntent(source(body: "let x = |")), .expression)
        XCTAssertEqual(try realIntent(source(body: "let |")), .declarationName)
        XCTAssertEqual(try realIntent(source(body: "println!(\"{}\", |)")), .expression)
        XCTAssertEqual(try realIntent(source(structBody: "label: |")), .typeName)
        XCTAssertEqual(try realIntent(source(file: "#[derive(|)]")), .preprocessor)
        XCTAssertEqual(try realIntent(source(file: "use std::{fs, |};")), .scopeAccess)
    }

    func testMultiLineConstructs() throws {
        let call = source(body: "let v = compute(\n            1,\n            |\n        );")
        XCTAssertEqual(try realIntent(call), .expression, "A new line of an argument list")
        let literal = source(body: "let c = Counter {\n            |\n        };")
        XCTAssertEqual(try realIntent(literal), .expression, "A new line of a struct literal")
        let parameters = source(file: "fn f(\n    a: u8,\n    |\n) {}")
        XCTAssertEqual(try realIntent(parameters), .declarationName, "A new line of a parameter list")
        let arm = source(body: "match by {\n            0 => {}\n            |\n        }")
        XCTAssertEqual(try realIntent(arm), .expression, "A new match arm")
    }

    func testCommentsAndStringsFromTheTree() throws {
        XCTAssertEqual(try realIntent(source(body: "// note |")), .comment)
        XCTAssertEqual(try realIntent(source(file: "/* outer\n/* inner */\nstill |\n*/")), .comment)
        XCTAssertEqual(try realIntent(source(body: "let s = \"first\nsecond |more\";")), .string)
        XCTAssertEqual(try realIntent(source(body: "let s = r#\"first\nsecond |more\"#;")), .string)
    }

    func testNodeNamesUsedByTheTablesExist() throws {
        let types = try nodeTypes(source(body: "self.count|;")).types
        XCTAssertTrue(types.contains("block"), "\(types)")
        XCTAssertTrue(types.contains("source_file"), "\(types)")
        let implTypes = try nodeTypes(source(impl: "|")).types
        XCTAssertTrue(implTypes.contains("declaration_list"), "\(implTypes)")
        let stringTypes = try nodeTypes(source(body: "let s = \"ab|c\";")).types
        XCTAssertEqual(stringTypes.first, "string_literal", "The literal is innermost inside its text")
        let attributeTypes = try nodeTypes(source(file: "#[derive(De|bug)]\nstruct S;")).types
        XCTAssertTrue(attributeTypes.contains("attribute_item"), "\(attributeTypes)")
    }
}
