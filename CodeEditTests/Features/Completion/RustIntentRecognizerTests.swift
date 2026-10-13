//
//  RustIntentRecognizerTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/13/26.
//

import XCTest
@testable import CodeEdit

/// Each row of the Rust intent table (``RustTokenRules``), with node types as the vendored grammar reports
/// them. ``RustIntentTreeTests`` parses whole documents with the real grammar.
final class RustIntentRecognizerTests: XCTestCase {
    /// Node ancestry in a function body.
    private let body = ["block", "function_item", "source_file"]
    /// Node ancestry in an `impl` body.
    private let implBody = ["declaration_list", "impl_item", "source_file"]
    /// Node ancestry at file scope.
    private let file = ["source_file"]
    /// Node ancestry in a struct body.
    private let structBody = ["field_declaration_list", "struct_item", "source_file"]
    /// Node ancestry in a struct literal.
    private let structLiteral = ["field_initializer_list", "struct_expression", "let_declaration", "block"]

    /// Recognizes the intent at the end of `line`, where the typed prefix is the trailing word, the way the
    /// aggregator splits it.
    private func intent(_ line: String, nodeTypes: [String] = []) -> CompletionIntent {
        let prefix = String(line.reversed().prefix { $0.isLetter || $0.isNumber || $0 == "_" }.reversed())
        return CompletionIntentRecognizer { _ in nodeTypes }
            .recognize(at: 0, prefix: prefix, lineTextBeforeCursor: line, languageId: "rust")
    }

    // MARK: - Member and path access

    func testMemberAccess() {
        XCTAssertEqual(intent("        self.", nodeTypes: body), .memberAccess)
        XCTAssertEqual(intent("        self.cou", nodeTypes: body), .memberAccess)
        XCTAssertEqual(intent("        let n = parse(s)?.", nodeTypes: body), .memberAccess)
        XCTAssertEqual(intent("        v.iter().ma", nodeTypes: body), .memberAccess)
        XCTAssertEqual(intent("        pair.0", nodeTypes: body), .memberAccess, "A tuple field, not a number")
        XCTAssertEqual(intent("            .ma", nodeTypes: body), .memberAccess, "A chain continued on a new line")
    }

    func testPathAccess() {
        XCTAssertEqual(intent("    let m = std::", nodeTypes: body), .scopeAccess)
        XCTAssertEqual(intent("    let m = std::collections::Has", nodeTypes: body), .scopeAccess)
        XCTAssertEqual(intent("    Self::", nodeTypes: implBody), .scopeAccess)
        XCTAssertEqual(intent("    crate::io::", nodeTypes: body), .scopeAccess)
    }

    func testUseDeclarations() {
        XCTAssertEqual(intent("use ", nodeTypes: file), .scopeAccess)
        XCTAssertEqual(intent("use st", nodeTypes: file), .scopeAccess)
        XCTAssertEqual(intent("use std::{", nodeTypes: file), .scopeAccess)
        XCTAssertEqual(intent("use std::{fs, ", nodeTypes: file), .scopeAccess)
        XCTAssertEqual(intent("pub use crate::", nodeTypes: file), .scopeAccess)
        XCTAssertEqual(intent("pub(crate) use super::", nodeTypes: file), .scopeAccess)
        XCTAssertEqual(intent("use std::io::Result as ", nodeTypes: file), .declarationName)
        XCTAssertEqual(intent("use std::fs; fn ", nodeTypes: file), .declarationName, "After the `use` ends")
    }

    // MARK: - New names

    func testDeclarationNames() {
        for line in [
            "    let ", "    let mut ", "fn ", "pub fn ", "struct ", "enum ", "trait ", "mod ", "const ",
            "static ", "static mut ", "type ", "    for ", "pub(crate) struct ", "    if let Some(ref "
        ] {
            XCTAssertEqual(intent(line, nodeTypes: file), .declarationName, line)
        }
        XCTAssertEqual(intent("    let va", nodeTypes: body), .declarationName)
        XCTAssertEqual(intent("macro_rules! ", nodeTypes: file), .declarationName)
    }

    func testParameterNames() {
        XCTAssertEqual(intent("fn add(", nodeTypes: file), .declarationName)
        XCTAssertEqual(intent("fn add(a: u8, ", nodeTypes: file), .declarationName)
        XCTAssertEqual(intent("fn map<T>(", nodeTypes: file), .declarationName)
        XCTAssertEqual(intent("    pub fn get(&", nodeTypes: implBody), .declarationName, "`&self`")
        XCTAssertEqual(intent("    v.iter().map(|", nodeTypes: body), .declarationName, "Closure parameters")
        XCTAssertEqual(intent("    v.iter().fold(0, |acc, ", nodeTypes: body), .declarationName)
        XCTAssertEqual(intent("    let f = move |", nodeTypes: body), .declarationName)
    }

    // MARK: - Types

    func testTypePositions() {
        for line in [
            "    let x: ", "fn f(a: ", "fn f(a: u8) -> ", "impl ", "impl<T> ", "impl Display for ",
            "    let e: Box<dyn ", "    let n = x as ", "fn f<T>() where ", "fn f<T: ", "struct S<T: Clone + ",
            "    let v: Vec<", "    let n = s.parse::<", "fn f(x: &", "fn f(x: &mut ", "fn f(x: &'a ",
            "fn f<'a>(x: &'", "const MAX: ", "static NAME: ", "type Alias = ", "    let p: *const ",
            "fn f(x: impl Iterator<Item = u8> + ", "    let m: HashMap<String, ", "pub struct S { field: "
        ] {
            XCTAssertEqual(intent(line, nodeTypes: file), .typeName, line)
        }
        XCTAssertEqual(intent("    name: ", nodeTypes: structBody), .typeName, "A field declaration")
        XCTAssertEqual(intent("    T: ", nodeTypes: ["where_clause", "function_item"]), .typeName)
        XCTAssertEqual(intent("    let f = |x: ", nodeTypes: body), .typeName)
    }

    // MARK: - Values

    func testExpressionPositions() {
        for line in [
            "    let x = ", "    return ", "        Some(v) => ", "    foo(", "    foo(a, ", "    if ",
            "    while ", "    match ", "    for x in ", "    if let ", "    while let ", "    let r = &",
            "    let r = &mut ", "    x += ", "    let ok = a && ", "    let n = a + ", "    let r = 0..",
            "    let v = [", "    let t = (", "    if a == ", "    if a < "
        ] {
            XCTAssertEqual(intent(line, nodeTypes: body), .expression, line)
        }
    }

    func testMacroCalls() {
        XCTAssertEqual(intent("    println!(", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    let v = vec![", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    format!(\"{}\", ", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    assert_eq!(a, ", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    println!(\"{na", nodeTypes: body), .string)
    }

    func testStructLiteralFields() {
        XCTAssertEqual(intent("    let p = Point { x: ", nodeTypes: body), .expression)
        XCTAssertEqual(intent("    let p = Point { x: 1, ", nodeTypes: body), .expression)
        XCTAssertEqual(intent("        x: ", nodeTypes: structLiteral), .expression, "A field on its own line")
        XCTAssertEqual(intent("    let p = Point {", nodeTypes: body), .expression)
    }

    // MARK: - Attributes

    func testAttributes() {
        for line in ["#[", "#![", "#[derive(", "#[derive(Debug, ", "    #[cfg(test", "#[cfg(feature = \"x\")] #["] {
            XCTAssertEqual(intent(line, nodeTypes: file), .preprocessor, line)
        }
        XCTAssertEqual(intent("#[test] fn ", nodeTypes: file), .declarationName, "After the attribute closes")
    }

    // MARK: - Scope

    func testStatementAndItemScope() {
        XCTAssertEqual(intent("    ", nodeTypes: body), .statement)
        XCTAssertEqual(intent("    pri", nodeTypes: body), .statement)
        XCTAssertEqual(intent("    ", nodeTypes: implBody), .topLevel)
        XCTAssertEqual(intent("", nodeTypes: file), .topLevel)
        XCTAssertEqual(intent("    ", nodeTypes: structBody), .declarationName)
        XCTAssertEqual(intent("    ", nodeTypes: ["enum_variant_list", "enum_item"]), .declarationName)
        XCTAssertEqual(intent("    let x = 1; ", nodeTypes: body), .statement)
        XCTAssertEqual(intent("    } else ", nodeTypes: body), .statement)
        XCTAssertEqual(intent("    if ready { ", nodeTypes: body), .statement)
        XCTAssertEqual(intent("    pub ", nodeTypes: implBody), .topLevel)
        XCTAssertEqual(intent("abc"), .unknown, "No tree and nothing on the line")
    }

    // MARK: - Literals and comments

    func testStringsCommentsAndNumbers() {
        XCTAssertEqual(intent("    let s = \"hel", nodeTypes: body), .string)
        XCTAssertEqual(intent("    let s = r#\"raw te", nodeTypes: body), .string)
        XCTAssertEqual(intent("    let c = 'a", nodeTypes: body), .string)
        XCTAssertEqual(intent("    let b = b'", nodeTypes: body), .string)
        XCTAssertEqual(intent("    // TODO wri", nodeTypes: body), .comment)
        XCTAssertEqual(intent("/// Docs wri", nodeTypes: file), .comment)
        XCTAssertEqual(intent("//! Crate do", nodeTypes: file), .comment)
        XCTAssertEqual(intent("    /* a /* b */ still in", nodeTypes: body), .comment)
        XCTAssertEqual(intent("    wri", nodeTypes: ["block_comment", "source_file"]), .comment, "Started earlier")
        XCTAssertEqual(intent("    wri", nodeTypes: ["string_content", "string_literal"]), .string)
        XCTAssertEqual(intent("    let n = 42", nodeTypes: body), .numberLiteral)
        XCTAssertEqual(intent("    let n = 1.5", nodeTypes: body), .numberLiteral)
    }

    func testLifetimes() {
        XCTAssertEqual(intent("fn f<'a>(x: &'a", nodeTypes: file), .typeName)
        XCTAssertEqual(intent("struct S<'", nodeTypes: file), .typeName)
    }

    // MARK: - Other languages

    func testOtherLanguagesAreUnchanged() {
        let recognizer = CompletionIntentRecognizer { _ in ["compound_statement"] }
        XCTAssertEqual(
            recognizer.recognize(at: 0, prefix: "", lineTextBeforeCursor: "    int ", languageId: "cpp"),
            .declarationName
        )
        XCTAssertEqual(
            recognizer.recognize(at: 0, prefix: "", lineTextBeforeCursor: "    std::", languageId: "cpp"),
            .scopeAccess
        )
    }
}
