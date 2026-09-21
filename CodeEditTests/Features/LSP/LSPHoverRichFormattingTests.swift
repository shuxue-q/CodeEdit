//
//  LSPHoverRichFormattingTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/16/26.
//

import XCTest
import SwiftUI
@testable import CodeEdit

final class LSPHoverRichFormattingTests: XCTestCase {
    // MARK: - Variable Declaration Line Breaking

    func testLongVariableDeclarationBreaksBeforeEqualSign() {
        let code = "let configurationOptionsForWorkspace: [String: Any] = [\"timeout\": 30, \"retries\": 3]"
        let formatted = LSPHoverDeclarationFormatter.format(code: code)
        XCTAssertTrue(formatted.contains("\n    = "))
        XCTAssertTrue(formatted.hasPrefix("let configurationOptionsForWorkspace: [String: Any]"))
    }

    func testLongVariableDeclarationBreaksBeforeColon() {
        let code = "var extremelyLongManagerInstanceIdentifierAcrossMultipleModules: NetworkServiceProtocol"
        let formatted = LSPHoverDeclarationFormatter.format(code: code)
        XCTAssertTrue(formatted.contains("\n    : "))
        XCTAssertTrue(
            formatted.hasPrefix("var extremelyLongManagerInstanceIdentifierAcrossMultipleModules")
        )
    }

    func testShortVariableDoesNotBreak() {
        let code = "let timeout = 30"
        let formatted = LSPHoverDeclarationFormatter.format(code: code)
        XCTAssertEqual(formatted, "let timeout = 30")
    }

    // MARK: - JSDoc and Sphinx Parsing

    func testJSDocParamAndReturnParsing() {
        let content = """
        ```javascript
        function authenticateUser(userId, token)
        ```
        Authenticates a user session.

        @param {string} userId The unique identifier for user.
        @param {string} [token] Optional authentication token.
        @return {Promise<boolean>} Resolves to true when authenticated.
        """

        let doc = LSPHoverParser.parse(content: content)
        XCTAssertNotNil(doc.declaration)
        XCTAssertEqual(doc.declaration?.symbolName, "authenticateUser")
        XCTAssertEqual(doc.parameters.count, 2)
        XCTAssertEqual(doc.parameters[0].name, "userId")
        XCTAssertEqual(doc.parameters[0].type, "string")
        XCTAssertEqual(doc.parameters[0].description, "The unique identifier for user.")
        XCTAssertEqual(doc.parameters[1].name, "token")
        XCTAssertEqual(doc.parameters[1].type, "string")
        XCTAssertEqual(doc.parameters[1].description, "Optional authentication token.")
        XCTAssertEqual(doc.returns, "{Promise<boolean>} Resolves to true when authenticated.")
    }

    func testSphinxPythonParamAndReturnParsing() {
        let content = """
        ```python
        def query_database(query_str: str, timeout: int = 30) -> list:
        ```
        Executes database query.

        :param str query_str: The raw SQL query string.
        :param int timeout: Connection timeout in seconds.
        :return: List of database records found.
        :raises DatabaseError: If connection cannot be established.
        """

        let doc = LSPHoverParser.parse(content: content)
        XCTAssertNotNil(doc.declaration)
        XCTAssertEqual(doc.declaration?.symbolName, "query_database")
        XCTAssertEqual(doc.parameters.count, 2)
        XCTAssertEqual(doc.parameters[0].name, "query_str")
        XCTAssertEqual(doc.parameters[0].type, "str")
        XCTAssertEqual(doc.parameters[0].description, "The raw SQL query string.")
        XCTAssertEqual(doc.parameters[1].name, "timeout")
        XCTAssertEqual(doc.parameters[1].type, "int")
        XCTAssertEqual(doc.returns, "List of database records found.")
        XCTAssertEqual(doc.throwsDescription, "DatabaseError: If connection cannot be established.")
    }

    func testPythonYieldsParsing() {
        let content = """
        ```python
        def item_generator(count: int):
        ```
        Yields sequential items.

        Yields:
            int: The next available item number.
        """

        let doc = LSPHoverParser.parse(content: content)
        XCTAssertEqual(doc.returns, "int: The next available item number.")
    }

    // MARK: - Markdown Headings & Lists

    func testMarkdownHeadingFormatting() {
        let text = "# Primary Heading\nContent under heading."
        let attributed = LSPCodeHighlighter.highlightInlineMarkdown(text: text, theme: nil)
        let plainText = String(attributed.characters)
        XCTAssertFalse(plainText.contains("# Primary Heading"))
        XCTAssertTrue(plainText.contains("Primary Heading"))
    }

    func testBulletListFormatting() {
        let text = "- First bullet point\n* Second bullet point"
        let attributed = LSPCodeHighlighter.highlightInlineMarkdown(text: text, theme: nil)
        let plainText = String(attributed.characters)
        XCTAssertTrue(plainText.contains("• First bullet point"))
        XCTAssertTrue(plainText.contains("• Second bullet point"))
    }

    func testNumberedListFormatting() {
        let text = "1. First step\n2. Second step"
        let attributed = LSPCodeHighlighter.highlightInlineMarkdown(text: text, theme: nil)
        let plainText = String(attributed.characters)
        XCTAssertTrue(plainText.contains("1. First step"))
        XCTAssertTrue(plainText.contains("2. Second step"))
    }

    func testDocLabelsFormatting() {
        let text = "Complexity: O(n log n)\nNote: Thread safe."
        let attributed = LSPCodeHighlighter.highlightInlineMarkdown(text: text, theme: nil)
        let plainText = String(attributed.characters)
        XCTAssertTrue(plainText.contains("Complexity: O(n log n)"))
        XCTAssertTrue(plainText.contains("Note: Thread safe."))
    }

    // MARK: - Inline Code Highlighting

    func testInlineCodeSpanTokenLevelHighlighting() {
        let text = "Use `let max: Int = 100` to configure."
        let attributed = LSPCodeHighlighter.highlightInlineMarkdown(text: text, theme: nil)
        let plainText = String(attributed.characters)
        XCTAssertTrue(plainText.contains("let max: Int = 100"))

        var codeRunFound = false
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            codeRunFound = true
            XCTAssertNotNil(run.backgroundColor)
        }
        XCTAssertTrue(codeRunFound)
    }

    // MARK: - Symbol Kind Classification

    func testSymbolKindDetection() {
        XCTAssertEqual(
            LSPHoverDeclaration.detectKind(rawCode: "func performTask()"),
            .function
        )
        XCTAssertEqual(
            LSPHoverDeclaration.detectKind(rawCode: "struct WorkspaceSettings"),
            .struct
        )
        XCTAssertEqual(
            LSPHoverDeclaration.detectKind(rawCode: "class DocumentController"),
            .class
        )
        XCTAssertEqual(
            LSPHoverDeclaration.detectKind(rawCode: "enum FileState"),
            .enum
        )
        XCTAssertEqual(
            LSPHoverDeclaration.detectKind(rawCode: "protocol ServiceProvider"),
            .protocol
        )
        XCTAssertEqual(
            LSPHoverDeclaration.detectKind(rawCode: "typealias Handler = () -> Void"),
            .typeAlias
        )
        XCTAssertEqual(
            LSPHoverDeclaration.detectKind(rawCode: "var isRunning: Bool"),
            .variable
        )
        XCTAssertEqual(
            LSPHoverDeclaration.detectKind(rawCode: "let maxAttempts = 5"),
            .constant
        )
        XCTAssertEqual(
            LSPHoverDeclaration.detectKind(rawCode: "#define BUFFER_CAPACITY 4096"),
            .macro
        )
    }

    func testSymbolKindProperties() {
        let funcKind = LSPHoverDeclaration.SymbolKind.function
        XCTAssertEqual(funcKind.title, "Function")
        XCTAssertEqual(funcKind.iconName, "function")

        let structKind = LSPHoverDeclaration.SymbolKind.struct
        XCTAssertEqual(structKind.title, "Structure")
        XCTAssertEqual(structKind.iconName, "square.3.layers.3d.down.right")
    }

    // MARK: - Discussion Code Blocks

    @MainActor
    func testDiscussionBlocksParseFencedCodeCorrectly() {
        let discussion = """
        Here is an example of calling this API:
        ```swift
        let client = APIClient()
        client.start()
        ```
        And some concluding text.
        """
        let blocks = LSPHoverView.parseDiscussionBlocks(discussion)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertFalse(blocks[0].isCode)
        XCTAssertEqual(blocks[0].text, "Here is an example of calling this API:")
        XCTAssertTrue(blocks[1].isCode)
        XCTAssertTrue(blocks[1].text.contains("let client = APIClient()"))
        XCTAssertTrue(blocks[1].text.contains("client.start()"))
        XCTAssertFalse(blocks[2].isCode)
        XCTAssertEqual(blocks[2].text, "And some concluding text.")
    }
}

// MARK: - Advanced Formatting & Parser Robustness Tests

extension LSPHoverRichFormattingTests {

    func testMultipleInlineCodePillsInSingleParagraph() {
        let text = "Use `first token` and `second token` to initialize."
        let attributed = LSPCodeHighlighter.highlightInlineMarkdown(text: text, theme: nil)
        let plainText = String(attributed.characters)
        XCTAssertTrue(plainText.contains("first token"))
        XCTAssertTrue(plainText.contains("second token"))

        var codeRunsCount = 0
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            codeRunsCount += 1
            XCTAssertNotNil(run.backgroundColor)
        }
        XCTAssertGreaterThanOrEqual(codeRunsCount, 2)
    }

    func testListItemsWithDocLabels() {
        let text = "- Note: Thread safe function.\n1. Complexity: O(n log n)"
        let attributed = LSPCodeHighlighter.highlightInlineMarkdown(text: text, theme: nil)
        let plainText = String(attributed.characters)
        XCTAssertTrue(plainText.contains("• Note: Thread safe function."))
        XCTAssertTrue(plainText.contains("1. Complexity: O(n log n)"))
    }

    func testLongReturnTypeDeclarationWrapping() {
        let code = "func fetchUserProfile(id: Int) -> AnyPublisher<UserProfile, NetworkError>"
        let formatted = LSPHoverDeclarationFormatter.format(code: code)
        XCTAssertTrue(formatted.contains("\n    id: Int\n)"))
        XCTAssertTrue(formatted.contains("-> AnyPublisher<UserProfile, NetworkError>"))
    }

    func testExistingMultiLineDeclarationPreservedWithoutExtraEmptyIndents() {
        let code = """
        func greet(
            name: String,
            loudly: Bool = false
        ) -> String
        """
        let formatted = LSPHoverDeclarationFormatter.format(code: code)
        XCTAssertFalse(formatted.contains("\n    \n"))
        XCTAssertTrue(formatted.contains("    name: String,"))
        XCTAssertTrue(formatted.contains("    loudly: Bool = false"))
    }

    func testSphinxMultiWordTypeParam() {
        let content = """
        ```python
        def lookup(key: str) -> str:
        ```
        :param dict[str, int] mapping: The mapping dictionary.
        :return: Lookup result.
        """
        let doc = LSPHoverParser.parse(content: content)
        XCTAssertEqual(doc.parameters.count, 1)
        XCTAssertEqual(doc.parameters[0].name, "mapping")
        XCTAssertEqual(doc.parameters[0].type, "dict[str, int]")
        XCTAssertEqual(doc.parameters[0].description, "The mapping dictionary.")
    }

    func testDocCommentSlashPrefixStripping() {
        let content = """
        ```swift
        func processItem(item: String) -> Bool
        ```
        /// Processes a single item in queue.
        /// - Parameter item: The item to process.
        /// - Returns: True if processed successfully.
        """
        let doc = LSPHoverParser.parse(content: content)
        XCTAssertEqual(doc.summary, "Processes a single item in queue.")
        XCTAssertEqual(doc.parameters.count, 1)
        XCTAssertEqual(doc.parameters[0].name, "item")
        XCTAssertEqual(doc.parameters[0].description, "The item to process.")
        XCTAssertEqual(doc.returns, "True if processed successfully.")
    }

    func testCppMacroPreprocessorDirectives() {
        let code = "#define BUFFER_SIZE 4096"
        let tokens = LSPCodeHighlighter.tokenize(code: code)
        XCTAssertEqual(tokens[0].text, "#define")
        XCTAssertEqual(tokens[0].kind, .keyword)

        let symbolToken = tokens.first { $0.text == "BUFFER_SIZE" }
        XCTAssertEqual(symbolToken?.kind, .symbolName)

        let numberToken = tokens.first { $0.text == "4096" }
        XCTAssertEqual(numberToken?.kind, .number)
    }

    func testHexAndUnderscoredNumbers() {
        let code = "let hex = 0x1A2B; let big = 1_000_000;"
        let tokens = LSPCodeHighlighter.tokenize(code: code)
        let hexToken = tokens.first { $0.text == "0x1A2B" }
        XCTAssertEqual(hexToken?.kind, .number)
        let bigToken = tokens.first { $0.text == "1_000_000" }
        XCTAssertEqual(bigToken?.kind, .number)
    }

    func testMultiLanguagePrimitiveTypes() {
        let code = "def f(a: str, b: list, c: usize, d: u8) -> boolean"
        let tokens = LSPCodeHighlighter.tokenize(code: code)
        let strToken = tokens.first { $0.text == "str" }
        XCTAssertEqual(strToken?.kind, .type)
        let listToken = tokens.first { $0.text == "list" }
        XCTAssertEqual(listToken?.kind, .type)
        let usizeToken = tokens.first { $0.text == "usize" }
        XCTAssertEqual(usizeToken?.kind, .type)
        let u8Token = tokens.first { $0.text == "u8" }
        XCTAssertEqual(u8Token?.kind, .type)
    }

    func testDiscussionHeaderStopsReturns() {
        let content = """
        ```swift
        func execute() -> Int
        ```
        - Returns: The exit code.
        ### Discussion
        Additional details that should not be in returns.
        """
        let doc = LSPHoverParser.parse(content: content)
        XCTAssertEqual(doc.returns, "The exit code.")
        XCTAssertEqual(doc.discussion, "### Discussion\nAdditional details that should not be in returns.")
    }
}
