//
//  PostfixTemplatesTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
@testable import CodeEdit

final class PostfixTemplatesTests: XCTestCase {
    private func labels(_ text: String, isTypeName: Bool = false, language: String = "cpp") -> [String] {
        let expression = PostfixTemplates.Expression(text: text, isTypeName: isTypeName)
        return PostfixTemplates.templates(for: expression, languageId: language).map(\.label)
    }

    private func expansion(
        _ label: String,
        of text: String,
        isTypeName: Bool = false,
        language: String = "cpp"
    ) throws -> String {
        let expression = PostfixTemplates.Expression(text: text, isTypeName: isTypeName)
        let template = try XCTUnwrap(
            PostfixTemplates.templates(for: expression, languageId: language).first { $0.label == label },
            "No `\(label)` template for \(language)"
        )
        return PostfixTemplates.expansion(of: template, for: expression, languageId: language)
    }

    // MARK: - Table

    func testTheCppTableHasEveryTemplateOfThePlan() {
        XCTAssertEqual(
            labels("ok", isTypeName: true),
            ["if", "else", "not", "while", "for", "fori", "forr", "return", "var", "new", "par", "cast", "switch", "nn"]
        )
    }

    func testCLacksTheCppOnlyTemplates() {
        let cLabels = labels("ok", isTypeName: true, language: "c")
        XCTAssertFalse(cLabels.contains("for"))
        XCTAssertFalse(cLabels.contains("new"))
        XCTAssertTrue(cLabels.contains("fori"))
        XCTAssertTrue(cLabels.contains("var"))
    }

    func testNewIsOnlyOfferedForTypeNames() {
        XCTAssertFalse(labels("widget").contains("new"))
        XCTAssertTrue(labels("Widget", isTypeName: true).contains("new"))
    }

    func testOtherLanguagesGetNothing() {
        XCTAssertTrue(labels("x", language: "python").isEmpty)
        XCTAssertTrue(labels("x", language: "cmake").isEmpty)
    }

    // MARK: - Expansions

    func testIfWhileReturnParAndSwitch() throws {
        XCTAssertEqual(try expansion("if", of: "ok"), "if (ok) {\n\t$0\n}")
        XCTAssertEqual(try expansion("else", of: "ok"), "if (!(ok)) {\n\t$0\n}")
        XCTAssertEqual(try expansion("while", of: "i < n"), "while (i < n) {\n\t$0\n}")
        XCTAssertEqual(try expansion("return", of: "a + b"), "return a + b;$0")
        XCTAssertEqual(try expansion("par", of: "a + b"), "(a + b)$0")
        XCTAssertEqual(try expansion("switch", of: "mode"), "switch (mode) {\n\tcase $1:\n\t\t$0\n}")
    }

    func testNotOmitsParenthesesForAnIdentifierOrACall() throws {
        XCTAssertEqual(try expansion("not", of: "ok"), "!ok$0")
        XCTAssertEqual(try expansion("not", of: "empty()"), "!empty()$0")
        XCTAssertEqual(try expansion("not", of: "node->next"), "!node->next$0")
        XCTAssertEqual(try expansion("not", of: "list.find(x)"), "!list.find(x)$0")
        XCTAssertEqual(try expansion("not", of: "a + b"), "!(a + b)$0")
        XCTAssertEqual(try expansion("not", of: "(a)"), "!((a))$0")
    }

    func testLoopTemplatesUseTabStopsAndMirrors() throws {
        XCTAssertEqual(try expansion("for", of: "items"), "for (const auto &${1:item} : items) {\n\t$0\n}")
        XCTAssertEqual(
            try expansion("fori", of: "items.size()"),
            "for (${1:size_t} ${2:i} = 0; $2 < items.size(); ++$2) {\n\t$0\n}"
        )
        XCTAssertEqual(
            try expansion("forr", of: "n"),
            "for (${1:size_t} ${2:i} = n - 1; $2 >= 0; --$2) {\n\t$0\n}"
        )
    }

    func testVarDependsOnTheLanguage() throws {
        XCTAssertEqual(try expansion("var", of: "compute()"), "auto ${1:name} = compute();$0")
        XCTAssertEqual(try expansion("var", of: "compute()", language: "c"), "${1:int} ${2:name} = compute();$0")
    }

    func testCastAndNullChecksDependOnTheLanguage() throws {
        XCTAssertEqual(try expansion("cast", of: "p"), "static_cast<${1:T}>(p)$0")
        XCTAssertEqual(try expansion("cast", of: "p", language: "c"), "(${1:T})p$0")
        XCTAssertEqual(try expansion("nn", of: "p"), "if (p != nullptr) {\n\t$0\n}")
        XCTAssertEqual(try expansion("nn", of: "p", language: "c"), "if (p != NULL) {\n\t$0\n}")
    }

    func testNewConstructsTheType() throws {
        XCTAssertEqual(try expansion("new", of: "Widget", isTypeName: true), "new Widget($0)")
    }

    func testSnippetSpecialCharactersInTheExpressionAreEscaped() throws {
        XCTAssertEqual(try expansion("if", of: #"s == "$x""#), #"if (s == "\$x") {"# + "\n\t$0\n}")
        XCTAssertEqual(try expansion("return", of: #"a[b}"#), #"return a[b\};$0"#)
        XCTAssertEqual(try expansion("par", of: #"'\n'"#), #"('\\n')$0"#)
    }

    // MARK: - Type names

    func testTypeNameHeuristic() {
        XCTAssertTrue(PostfixTemplates.looksLikeTypeName("Widget"))
        XCTAssertTrue(PostfixTemplates.looksLikeTypeName("ui::Widget"))
        XCTAssertTrue(PostfixTemplates.looksLikeTypeName("std::string"))
        XCTAssertTrue(PostfixTemplates.looksLikeTypeName("std::vector<int>"))
        XCTAssertTrue(PostfixTemplates.looksLikeTypeName("int"))
        XCTAssertFalse(PostfixTemplates.looksLikeTypeName("widget"))
        XCTAssertFalse(PostfixTemplates.looksLikeTypeName("make_widget()"))
        XCTAssertFalse(PostfixTemplates.looksLikeTypeName("a.b"))
    }

    func testDetailShowsTheExpressionTruncated() throws {
        let expression = PostfixTemplates.Expression(text: "a_rather_long_expression_name.size()")
        let template = try XCTUnwrap(PostfixTemplates.all.first { $0.label == "if" })
        XCTAssertEqual(PostfixTemplates.detail(of: template, for: expression), "if (a_rather_long_expressio…) {…}")
        let short = PostfixTemplates.Expression(text: "ok")
        XCTAssertEqual(PostfixTemplates.detail(of: template, for: short), "if (ok) {…}")
    }
}
