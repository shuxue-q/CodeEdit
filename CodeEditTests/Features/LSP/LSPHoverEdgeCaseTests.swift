//
//  LSPHoverEdgeCaseTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/16/26.
//

import XCTest
import SwiftUI
@testable import CodeEdit

final class LSPHoverEdgeCaseTests: XCTestCase {
    // MARK: - Multi-Language & Edge-Case Tests

    func testClangdHoverParsingWithHeaderAndCppSignature() {
        let content = """
        ### function `calculateTotal`
        ```cpp
        int calculateTotal(int price, int tax, int discount, int shipping)
        ```
        ---
        Calculates the total cost.

        @param price The item price.
        @param tax The tax amount.
        @return The total cost.
        """

        let doc = LSPHoverParser.parse(content: content)
        XCTAssertNotNil(doc.declaration)
        XCTAssertEqual(doc.declaration?.symbolName, "calculateTotal")
        XCTAssertTrue(doc.declaration?.code.contains("\n") == true)
        XCTAssertEqual(doc.summary, "Calculates the total cost.")
        XCTAssertEqual(doc.parameters.count, 2)
        XCTAssertEqual(doc.parameters[0].name, "price")
        XCTAssertEqual(doc.returns, "The total cost.")
    }

    func testRustHoverParsingWithLifetimeAndSecondBlock() {
        let content = """
        ```rust
        my_crate::parser
        ```
        ```rust
        pub fn parse_input<'a>(input: &'a str, buffer: &'a mut [u8], max_len: usize) -> Result<&'a str, Error>
        ```
        ---
        Parses raw input buffer.
        """

        let doc = LSPHoverParser.parse(content: content)
        XCTAssertNotNil(doc.declaration)
        XCTAssertEqual(doc.declaration?.symbolName, "parse_input")
        XCTAssertTrue(doc.declaration?.code.contains("\n") == true)
        XCTAssertEqual(doc.summary, "Parses raw input buffer.")

        // Verify lifetime tokenization does not consume the rest as an unclosed string
        let tokens = LSPCodeHighlighter.tokenize(code: doc.declaration?.code ?? "")
        let stringTokens = tokens.filter { $0.kind == .string }
        XCTAssertTrue(stringTokens.isEmpty)
        let typeTokens = tokens.filter { $0.kind == .type }
        XCTAssertTrue(typeTokens.contains { $0.text == "'a" })
    }

    func testPythonHoverParsingWithFunctionPrefix() {
        let content = """
        ```python
        (function) def connect(host: str, port: int = 8080, timeout: float = 30.0, retry: bool = True) -> bool:
        ```
        Establishes socket connection.

        Args:
            host (str): Destination hostname.
            port (int): Port number.
        """

        let doc = LSPHoverParser.parse(content: content)
        XCTAssertNotNil(doc.declaration)
        XCTAssertEqual(doc.declaration?.symbolName, "connect")
        XCTAssertFalse(doc.declaration?.code.hasPrefix("(function)") ?? true)
        XCTAssertTrue(doc.declaration?.code.contains("\n") == true)
        XCTAssertEqual(doc.parameters.count, 2)
        XCTAssertEqual(doc.parameters[0].name, "host")
        XCTAssertEqual(doc.parameters[1].name, "port")
    }

    func testAttributedSignatureFormatting() {
        let code = "@available(macOS 14.0, *) func performAction("
            + "actionName: String, timeout: TimeInterval, retries: Int, priority: TaskPriority"
            + ") async throws -> Void"
        let formatted = LSPHoverDeclarationFormatter.format(code: code)
        XCTAssertTrue(formatted.hasPrefix("@available(macOS 14.0, *) func performAction("))
        XCTAssertTrue(formatted.contains("    actionName: String,"))
        XCTAssertTrue(formatted.contains("    timeout: TimeInterval,"))
        XCTAssertTrue(formatted.contains(") async throws -> Void"))
    }

    func testSwiftInitAndSubscriptSymbolNames() {
        let initCode = "init(title: String, frame: CGRect, isVisible: Bool = true)"
        XCTAssertEqual(LSPHoverSectionExtractor.extractSymbolName(from: initCode), "init")

        let subscriptCode = "subscript(key: String, default defaultValue: Value) -> Value"
        XCTAssertEqual(LSPHoverSectionExtractor.extractSymbolName(from: subscriptCode), "subscript")
    }

    func testTypedVariableSymbolNames() {
        let cppConst = "const double MAX_SPEED = 120.0;"
        XCTAssertEqual(LSPHoverSectionExtractor.extractSymbolName(from: cppConst), "MAX_SPEED")

        let cppVar = "int counter = 0;"
        XCTAssertEqual(LSPHoverSectionExtractor.extractSymbolName(from: cppVar), "counter")

        let swiftTypealias = "typealias CompletionHandler = (Result<Data, Error>) -> Void"
        XCTAssertEqual(LSPHoverSectionExtractor.extractSymbolName(from: swiftTypealias), "CompletionHandler")
    }

    func testValueAndTypeDistinction() {
        let code = "let flag: Bool = true"
        let tokens = LSPCodeHighlighter.tokenize(code: code)

        let boolToken = tokens.first { $0.text == "Bool" }
        XCTAssertEqual(boolToken?.kind, .type)

        let trueToken = tokens.first { $0.text == "true" }
        XCTAssertEqual(trueToken?.kind, .value)

        let letToken = tokens.first { $0.text == "let" }
        XCTAssertEqual(letToken?.kind, .keyword)

        let flagToken = tokens.first { $0.text == "flag" }
        XCTAssertEqual(flagToken?.kind, .symbolName)

        let cCode = "int counter = 0;"
        let cTokens = LSPCodeHighlighter.tokenize(code: cCode)
        let intToken = cTokens.first { $0.text == "int" }
        XCTAssertEqual(intToken?.kind, .type)
    }

    func testDiscussionCodeBlocksDoNotProduceFakeParameters() {
        let content = """
        ```swift
        func execute()
        ```
        Executes the command.

        ### Discussion
        Here is how to configure it:
        ```swift
        let config: Config = Config()
        config.timeout = 30
        ```
        Notice: do not run in main thread.
        """

        let doc = LSPHoverParser.parse(content: content)
        XCTAssertTrue(doc.parameters.isEmpty)
        XCTAssertNotNil(doc.discussion)
        XCTAssertTrue(doc.discussion?.contains("let config: Config = Config()") == true)
        XCTAssertTrue(doc.discussion?.contains("Notice: do not run in main thread.") == true)
    }

    func testClangdNamespaceWithEmDashDivider() {
        let content = """
        namespace core———// In namespace avx
        namespace core {}
        """

        let doc = LSPHoverParser.parse(content: content)
        XCTAssertNotNil(doc.declaration)
        XCTAssertEqual(doc.declaration?.rawCode, "namespace core")
        XCTAssertEqual(doc.declaration?.symbolName, "core")
        XCTAssertEqual(doc.summary, "// In namespace avx")
        XCTAssertEqual(doc.discussion, "namespace core {}")

        // Test declaration tokenization has namespace as keyword and core as symbolName
        let tokens = LSPCodeHighlighter.tokenize(
            code: doc.declaration?.code ?? "",
            symbolName: doc.declaration?.symbolName
        )
        let namespaceToken = tokens.first { $0.text == "namespace" }
        XCTAssertEqual(namespaceToken?.kind, .keyword)
        let coreToken = tokens.first { $0.text == "core" }
        XCTAssertEqual(coreToken?.kind, .symbolName)
    }

    func testClangdNamespaceWithHyphenDividers() {
        let content = """
        namespace core
        ---
        // In namespace avx
        namespace core {}
        """

        let doc = LSPHoverParser.parse(content: content)
        XCTAssertNotNil(doc.declaration)
        XCTAssertEqual(doc.declaration?.rawCode, "namespace core")
        XCTAssertEqual(doc.declaration?.symbolName, "core")
        XCTAssertEqual(doc.summary, "// In namespace avx")
        XCTAssertEqual(doc.discussion, "namespace core {}")
    }

    func testConstructorAndDestructorDeclarations() {
        let ctor = "ThreadPool(size_t workers = 4)"
        var textCtor = ctor
        let declCtor = LSPHoverParser.extractLeadingSignature(&textCtor, fallbackLanguage: "cpp")
        XCTAssertNotNil(declCtor)
        XCTAssertEqual(declCtor?.rawCode, ctor)
        XCTAssertEqual(declCtor?.symbolName, "ThreadPool")

        let dtor = "~ThreadPool()"
        var textDtor = dtor
        let declDtor = LSPHoverParser.extractLeadingSignature(&textDtor, fallbackLanguage: "cpp")
        XCTAssertNotNil(declDtor)
        XCTAssertEqual(declDtor?.rawCode, dtor)
        XCTAssertEqual(declDtor?.symbolName, "~ThreadPool")

        let qualified = "core::ThreadPool"
        var textQualified = qualified
        let declQualified = LSPHoverParser.extractLeadingSignature(&textQualified, fallbackLanguage: "cpp")
        XCTAssertNotNil(declQualified)
        XCTAssertEqual(declQualified?.rawCode, qualified)
        XCTAssertEqual(declQualified?.symbolName, "ThreadPool")

        let qualifiedCtor = "core::ThreadPool(int workers)"
        var textQualifiedCtor = qualifiedCtor
        let declQualifiedCtor = LSPHoverParser.extractLeadingSignature(&textQualifiedCtor, fallbackLanguage: "cpp")
        XCTAssertNotNil(declQualifiedCtor)
        XCTAssertEqual(declQualifiedCtor?.symbolName, "ThreadPool")
    }

    func testLineBreaksPreservedInMarkdownAndComments() {
        let multiLine = """
        First line of documentation.
        Second line of documentation.
        Third line of documentation.
        """
        let attributed = LSPCodeHighlighter.highlightInlineMarkdown(text: multiLine, theme: nil)
        let plainText = String(attributed.characters)
        XCTAssertTrue(plainText.contains("First line of documentation.\nSecond line of documentation."))
        XCTAssertTrue(plainText.contains("Second line of documentation.\nThird line of documentation."))
    }

    func testHighlightCommentsAndDefinitionsWithoutCodeFences() {
        let commentText = "// In namespace avx"
        let commentTokens = LSPCodeHighlighter.tokenize(code: commentText)
        XCTAssertEqual(commentTokens.first?.kind, .comment)

        let defText = "namespace core {}"
        let defTokens = LSPCodeHighlighter.tokenize(code: defText)
        let keywordToken = defTokens.first { $0.text == "namespace" }
        XCTAssertEqual(keywordToken?.kind, .keyword)
        let symbolToken = defTokens.first { $0.text == "core" }
        XCTAssertEqual(symbolToken?.kind, .symbolName)
    }
}

// MARK: - Advanced Edge Cases

extension LSPHoverEdgeCaseTests {
    func testInlineDividersWithVariousGlyphs() {
        let hyphenContent = "namespace core --- // In namespace avx\nnamespace core {}"
        let docHyphen = LSPHoverParser.parse(content: hyphenContent)
        XCTAssertEqual(docHyphen.declaration?.rawCode, "namespace core")
        XCTAssertEqual(docHyphen.summary, "// In namespace avx")
        XCTAssertEqual(docHyphen.discussion, "namespace core {}")

        let asteriskContent = "namespace core *** // In namespace avx\nnamespace core {}"
        let docAsterisk = LSPHoverParser.parse(content: asteriskContent)
        XCTAssertEqual(docAsterisk.declaration?.rawCode, "namespace core")
        XCTAssertEqual(docAsterisk.summary, "// In namespace avx")

        let singleEmDash = "namespace core — // In namespace avx\nnamespace core {}"
        let docSingle = LSPHoverParser.parse(content: singleEmDash)
        XCTAssertEqual(docSingle.declaration?.rawCode, "namespace core")
        XCTAssertEqual(docSingle.summary, "// In namespace avx")
    }

    func testMultiLineTemplateDeclarations() {
        var textFunc = "template <typename T>\nvoid process(T val)\n---\nProcesses val."
        let declFunc = LSPHoverParser.extractLeadingSignature(&textFunc, fallbackLanguage: "cpp")
        XCTAssertNotNil(declFunc)
        XCTAssertEqual(declFunc?.symbolName, "process")
        XCTAssertTrue(declFunc?.rawCode.contains("template <typename T>") == true)
        XCTAssertTrue(declFunc?.rawCode.contains("void process(T val)") == true)

        var textConcept = "template <typename T, typename U>\nconcept MyConcept = true;\n---\nConcept doc."
        let declConcept = LSPHoverParser.extractLeadingSignature(&textConcept, fallbackLanguage: "cpp")
        XCTAssertNotNil(declConcept)
        XCTAssertEqual(declConcept?.symbolName, "MyConcept")
    }

    func testCppFunctionsReturningTemplateTypes() {
        let vectorFunc = "std::vector<int> getValues()"
        XCTAssertEqual(LSPHoverSectionExtractor.extractSymbolName(from: vectorFunc), "getValues")

        let uniquePtrFunc = "std::unique_ptr<ThreadPool> makePool(size_t workers)"
        XCTAssertEqual(LSPHoverSectionExtractor.extractSymbolName(from: uniquePtrFunc), "makePool")

        let templatedFunc = "template <typename T> std::vector<T> loadItems<T>(int limit)"
        XCTAssertEqual(LSPHoverSectionExtractor.extractSymbolName(from: templatedFunc), "loadItems")
    }

    func testTypedefAndStorageSpecifierVariables() {
        let typedefDecl = "typedef int MyInt;"
        XCTAssertEqual(LSPHoverSectionExtractor.extractSymbolName(from: typedefDecl), "MyInt")

        let constexprDecl = "constexpr double Pi = 3.14159;"
        XCTAssertEqual(LSPHoverSectionExtractor.extractSymbolName(from: constexprDecl), "Pi")

        let externDecl = "extern int global_counter;"
        XCTAssertEqual(LSPHoverSectionExtractor.extractSymbolName(from: externDecl), "global_counter")

        let inlineDecl = "inline constexpr int BufferSize = 1024;"
        XCTAssertEqual(LSPHoverSectionExtractor.extractSymbolName(from: inlineDecl), "BufferSize")
    }

    func testCppOperatorOverloads() {
        let equalsOp = "bool operator==(const Foo& other)"
        XCTAssertEqual(LSPHoverSectionExtractor.extractSymbolName(from: equalsOp), "operator==")

        let notEqualsOp = "bool operator!=(const Foo& other)"
        XCTAssertEqual(LSPHoverSectionExtractor.extractSymbolName(from: notEqualsOp), "operator!=")
    }

    func testConstructorStopwordsAndEnglishProse() {
        var prose = "ThreadPool(workers) creates a pool of workers."
        let declProse = LSPHoverParser.extractLeadingSignature(&prose, fallbackLanguage: "cpp")
        XCTAssertNil(declProse)

        var ctor = "ThreadPool(size_t workers = 4)"
        let declCtor = LSPHoverParser.extractLeadingSignature(&ctor, fallbackLanguage: "cpp")
        XCTAssertNotNil(declCtor)
        XCTAssertEqual(declCtor?.symbolName, "ThreadPool")
    }
}
