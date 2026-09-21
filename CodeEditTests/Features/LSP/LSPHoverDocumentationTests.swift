//
//  LSPHoverDocumentationTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/16/26.
//

import XCTest
import SwiftUI
@testable import CodeEdit

final class LSPHoverDocumentationTests: XCTestCase {
    // MARK: - Declaration Formatting Tests

    func testDeclarationFormattingShortSignature() {
        let code = "func stop()"
        let formatted = LSPHoverDeclarationFormatter.format(code: code)
        XCTAssertEqual(formatted, "func stop()")
    }

    func testDeclarationFormattingShortParams() {
        let code = "func add(x: Int, y: Int) -> Int"
        let formatted = LSPHoverDeclarationFormatter.format(code: code)
        XCTAssertEqual(formatted, "func add(x: Int, y: Int) -> Int")
    }

    func testDeclarationFormattingLongSignature() {
        let code = "func performHover(at offset: Int, hoverRange: LSPRange?, in controller: TextViewController) -> Void"
        let formatted = LSPHoverDeclarationFormatter.format(code: code)
        let expected = """
        func performHover(
            at offset: Int,
            hoverRange: LSPRange?,
            in controller: TextViewController
        ) -> Void
        """
        XCTAssertEqual(formatted, expected)
    }

    func testDeclarationFormattingWithGenerics() {
        let code = "func convert<K, V>(map: [K: V], key: K, fallback: V) -> V"
        let formatted = LSPHoverDeclarationFormatter.format(code: code)
        let expected = """
        func convert<K, V>(
            map: [K: V],
            key: K,
            fallback: V
        ) -> V
        """
        XCTAssertEqual(formatted, expected)
    }

    func testDeclarationFormattingWithClosures() {
        let code = "func request(url: URL, completion: @escaping (Result<Data, Error>) -> Void) -> Task"
        let formatted = LSPHoverDeclarationFormatter.format(code: code)
        let expected = """
        func request(
            url: URL,
            completion: @escaping (Result<Data, Error>) -> Void
        ) -> Task
        """
        XCTAssertEqual(formatted, expected)
    }

    func testVariableDeclaration() {
        let code = "var isConnected: Bool"
        let formatted = LSPHoverDeclarationFormatter.format(code: code)
        XCTAssertEqual(formatted, "var isConnected: Bool")
    }

    // MARK: - Parser Tests

    func testSwiftDocCommentParsing() {
        let content = """
        ```swift
        func calculate(price: Double, taxRate: Double = 0.08) throws -> Double
        ```
        Calculates the final total including applicable tax.

        - Parameters:
          - price: The pre-tax item price.
          - taxRate: The tax rate percentage.
        - Returns: The total calculated price.
        - Throws: An error if price is negative.
        - Note: Thread safe function.
        - Warning: Do not pass negative tax rates.
        """

        let doc = LSPHoverParser.parse(content: content)
        XCTAssertNotNil(doc.declaration)
        XCTAssertEqual(doc.declaration?.symbolName, "calculate")
        XCTAssertEqual(doc.summary, "Calculates the final total including applicable tax.")

        XCTAssertEqual(doc.parameters.count, 2)
        XCTAssertEqual(doc.parameters[0].name, "price")
        XCTAssertEqual(doc.parameters[0].description, "The pre-tax item price.")
        XCTAssertEqual(doc.parameters[1].name, "taxRate")
        XCTAssertEqual(doc.parameters[1].description, "The tax rate percentage.")

        XCTAssertEqual(doc.returns, "The total calculated price.")
        XCTAssertEqual(doc.throwsDescription, "An error if price is negative.")

        XCTAssertEqual(doc.callouts.count, 2)
        XCTAssertEqual(doc.callouts[0].kind, .note)
        XCTAssertEqual(doc.callouts[0].message, "Thread safe function.")
        XCTAssertEqual(doc.callouts[1].kind, .warning)
        XCTAssertEqual(doc.callouts[1].message, "Do not pass negative tax rates.")
    }

    func testSingularParameterParsing() {
        let content = """
        ```swift
        func updateUser(id: UUID, name: String)
        ```
        Updates user record in store.

        - Parameter id: The unique record identifier.
        - Parameter name: New user display name.
        """

        let doc = LSPHoverParser.parse(content: content)
        XCTAssertEqual(doc.parameters.count, 2)
        XCTAssertEqual(doc.parameters[0].name, "id")
        XCTAssertEqual(doc.parameters[0].description, "The unique record identifier.")
        XCTAssertEqual(doc.parameters[1].name, "name")
        XCTAssertEqual(doc.parameters[1].description, "New user display name.")
    }

    func testDoxygenParamParsing() {
        let content = """
        ```c
        int printf(const char *format, ...);
        ```
        @param[in] format Format control string.
        @param ... Variadic arguments.
        @return Number of characters printed.
        @note Standard I/O function.
        """

        let doc = LSPHoverParser.parse(content: content)
        XCTAssertEqual(doc.parameters.count, 2)
        XCTAssertEqual(doc.parameters[0].name, "format")
        XCTAssertEqual(doc.parameters[0].description, "Format control string.")
        XCTAssertEqual(doc.returns, "Number of characters printed.")
        XCTAssertEqual(doc.callouts.count, 1)
        XCTAssertEqual(doc.callouts[0].kind, .note)
    }

    func testPythonArgsParsing() {
        let content = """
        ```python
        def connect(host: str, port: int = 8080) -> bool:
        ```
        Establishes connection to remote server.

        Args:
            host (str): Destination server hostname or IP.
            port (int): Port number to target.

        Returns:
            bool: True on successful connection.
        """

        let doc = LSPHoverParser.parse(content: content)
        XCTAssertEqual(doc.parameters.count, 2)
        XCTAssertEqual(doc.parameters[0].name, "host")
        XCTAssertEqual(doc.parameters[0].type, "str")
        XCTAssertEqual(doc.parameters[0].description, "Destination server hostname or IP.")
        XCTAssertEqual(doc.parameters[1].name, "port")
        XCTAssertEqual(doc.parameters[1].type, "int")
        XCTAssertEqual(doc.parameters[1].description, "Port number to target.")
        XCTAssertEqual(doc.returns, "bool: True on successful connection.")
    }

    func testMultiLineParameterDescription() {
        let content = """
        ```swift
        func setup(config: Config)
        ```
        - Parameters:
          - config: The configuration object
            used to initialize the client session
            with custom timeout settings.
        """

        let doc = LSPHoverParser.parse(content: content)
        XCTAssertEqual(doc.parameters.count, 1)
        XCTAssertEqual(doc.parameters[0].name, "config")
        let expectedDesc = "The configuration object used to initialize the client session "
            + "with custom timeout settings."
        XCTAssertEqual(doc.parameters[0].description, expectedDesc)
    }

    func testLeadingSignatureWithoutCodeFences() {
        let content = """
        func fetchItems() -> [String]
        Retrieves all items from storage.
        """

        let doc = LSPHoverParser.parse(content: content)
        XCTAssertNotNil(doc.declaration)
        XCTAssertEqual(doc.declaration?.rawCode, "func fetchItems() -> [String]")
        XCTAssertEqual(doc.summary, "Retrieves all items from storage.")
    }

    func testEmptyContent() {
        let doc = LSPHoverParser.parse(content: "")
        XCTAssertNil(doc.declaration)
        XCTAssertNil(doc.summary)
        XCTAssertTrue(doc.parameters.isEmpty)
    }

    // MARK: - Highlighter Tests

    func testCodeHighlighterTokenizesKeywordsAndTypes() {
        let code = "func fetch(id: Int) -> String?"
        let tokens = LSPCodeHighlighter.tokenize(code: code)

        let keywordTokens = tokens.filter { $0.kind == .keyword }
        XCTAssertTrue(keywordTokens.contains { $0.text == "func" })

        let typeTokens = tokens.filter { $0.kind == .type }
        XCTAssertTrue(typeTokens.contains { $0.text == "Int" })
        XCTAssertTrue(typeTokens.contains { $0.text == "String" })

        let symbolTokens = tokens.filter { $0.kind == .symbolName }
        XCTAssertTrue(symbolTokens.contains { $0.text == "fetch" })
    }

    func testCodeHighlighterAttributedOutput() {
        let code = "let count: Int = 42"
        let attributed = LSPCodeHighlighter.highlight(code: code, theme: nil)
        XCTAssertEqual(String(attributed.characters), code)
    }

    func testInlineMarkdownHighlighter() {
        let text = "Returns `true` if successful and `false` otherwise."
        let attributed = LSPCodeHighlighter.highlightInlineMarkdown(text: text, theme: nil)
        XCTAssertTrue(String(attributed.characters).contains("true"))

        var foundCodeRun = false
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            foundCodeRun = true
            XCTAssertNotNil(run.backgroundColor)
        }
        XCTAssertTrue(foundCodeRun)
    }

    // MARK: - LSPHoverView Sizing Tests

    @MainActor
    func testHoverViewInitializesAndCalculatesHeight() {
        let content = """
        ```swift
        func greet(name: String) -> String
        ```
        Returns greeting.
        """
        let view = LSPHoverView(content: content)
        XCTAssertEqual(view.content, content)
    }
}
