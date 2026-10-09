//
//  AICompletionPromptTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import CodeEditLanguages
import SwiftTreeSitter
import XCTest

@testable import CodeEdit

final class AICompletionPromptTests: XCTestCase {
    private func context(
        text: String = "int main() {\n    pri\n}\n",
        offset: Int = 20,
        expectedType: String? = nil,
        receiverType: String? = nil
    ) -> CompletionContext {
        var context = CompletionContext(
            prefix: "pri",
            prefixRange: NSRange(location: 17, length: 3),
            triggerCharacter: nil,
            intent: .statement,
            languageId: "cpp",
            documentText: text,
            cursorOffset: offset
        )
        context.expectedType = expectedType.flatMap { TypeText.parse($0) }
        context.receiverType = receiverType
        return context
    }

    // MARK: - Extra lines only when known

    func testWithoutSemanticFactsTheMessageIsUnchanged() {
        let message = AICompletionPrompt.userMessage(for: AICompletionPrompt.request(for: context()))
        XCTAssertEqual(message, """
        Language: cpp
        The user is typing a statement.
        Code before the cursor:
        int main() {
            pri<cursor/>
        }

        """)
    }

    func testTheExpectedTypeAppearsOnlyWhenKnown() {
        let known = AICompletionPrompt.userMessage(
            for: AICompletionPrompt.request(for: context(expectedType: "std::string"))
        )
        XCTAssertTrue(known.contains("The expression should produce a `std::string`."))
        let unknown = AICompletionPrompt.userMessage(for: AICompletionPrompt.request(for: context()))
        XCTAssertFalse(unknown.contains("should produce"))
    }

    func testTheReceiverTypeAppearsOnlyWhenKnown() {
        let known = AICompletionPrompt.userMessage(
            for: AICompletionPrompt.request(for: context(receiverType: "std::vector<int>"))
        )
        XCTAssertTrue(known.contains("The object before the cursor has the type `std::vector<int>`."))
        XCTAssertFalse(AICompletionPrompt.userMessage(for: AICompletionPrompt.request(for: context()))
            .contains("object before the cursor"))
    }

    func testTheFunctionSignatureAppearsOnlyWhenKnown() {
        let semantics = ResolvedSemantics(functionSignature: "int add(int a, int b)")
        let request = AICompletionPrompt.request(for: context(), semantics: semantics)
        let message = AICompletionPrompt.userMessage(for: request)
        XCTAssertTrue(message.contains("The cursor is inside this function: `int add(int a, int b)`."))
    }

    func testTheExtraLinesComeBeforeTheCode() throws {
        let semantics = ResolvedSemantics(
            expectedType: TypeText.parse("int"), receiverType: "Foo", functionSignature: "void f()"
        )
        let request = AICompletionPrompt.request(for: context(), semantics: semantics)
        let message = AICompletionPrompt.userMessage(for: request)
        let function = try XCTUnwrap(message.range(of: "inside this function"))
        let expected = try XCTUnwrap(message.range(of: "should produce"))
        let receiver = try XCTUnwrap(message.range(of: "object before the cursor"))
        let code = try XCTUnwrap(message.range(of: "Code before the cursor:"))
        XCTAssertLessThan(function.lowerBound, expected.lowerBound)
        XCTAssertLessThan(expected.lowerBound, receiver.lowerBound)
        XCTAssertLessThan(receiver.lowerBound, code.lowerBound)
    }

    func testTypesAlreadyOnTheContextWinOverResolvedOnes() {
        let semantics = ResolvedSemantics(expectedType: TypeText.parse("long"), receiverType: "Late")
        let request = AICompletionPrompt.request(
            for: context(expectedType: "int", receiverType: "Early"), semantics: semantics
        )
        XCTAssertEqual(request.expectedType, "int")
        XCTAssertEqual(request.receiverType, "Early")
    }

    // MARK: - Size caps

    func testTheCodeWindowsAreCapped() {
        let text = String(repeating: "a", count: 10_000) + "|" + String(repeating: "b", count: 10_000)
        let request = AICompletionPrompt.request(for: context(text: text, offset: 10_000))
        XCTAssertEqual(request.before.count, 4_000)
        XCTAssertEqual(request.after.count, 1_000)
    }

    func testTheExtraLinesNeverExceedTheirBudget() throws {
        let longType = String(repeating: "T", count: 1_000)
        let longSignature = String(repeating: "x", count: 1_000)
        let request = AICompletionRequest(
            before: "", after: "", prefix: "", languageId: "cpp", intentDescription: "code",
            expectedType: longType, receiverType: longType, functionSignature: longSignature
        )
        let extra = try XCTUnwrap(AICompletionPrompt.extraContext(for: request))
        XCTAssertLessThanOrEqual(extra.count, AICompletionPrompt.maxExtraContextLength)
        XCTAssertEqual(AICompletionPrompt.maxExtraContextLength, 600)
    }

    func testBackticksAndNewlinesCannotBreakOutOfTheLine() throws {
        let request = AICompletionRequest(
            before: "", after: "", prefix: "", languageId: "cpp", intentDescription: "code",
            expectedType: "a`b\nc"
        )
        let extra = try XCTUnwrap(AICompletionPrompt.extraContext(for: request))
        XCTAssertEqual(extra, "The expression should produce a `a'b c`.")
    }

    func testNothingKnownMeansNoExtraContext() {
        let request = AICompletionRequest(
            before: "", after: "", prefix: "", languageId: "cpp", intentDescription: "code"
        )
        XCTAssertNil(AICompletionPrompt.extraContext(for: request))
    }
}

final class FunctionSignatureTextTests: XCTestCase {
    func testTheHeaderStopsAtTheBodyAndIsOneLine() {
        let text = "static int\nadd(int a,\n    int b)\n{\n    return a + b;\n}\n"
        let bodyStart = (text as NSString).range(of: "{").location
        XCTAssertEqual(
            FunctionSignatureText.signature(in: text, functionStart: 0, bodyStart: bodyStart),
            "static int add(int a, int b)"
        )
    }

    func testAMissingBodyReadsToTheEndOfTheText() {
        let signature = FunctionSignatureText.signature(in: "void f(int x)", functionStart: 0, bodyStart: nil)
        XCTAssertEqual(signature, "void f(int x)")
    }

    func testALongHeaderIsCapped() {
        let text = "void f(" + String(repeating: "int a, ", count: 200) + ")"
        let signature = FunctionSignatureText.signature(in: text, functionStart: 0, bodyStart: nil)
        XCTAssertEqual(signature?.count, FunctionSignatureText.maxLength)
    }

    func testOutOfRangeOffsetsYieldNothing() {
        XCTAssertNil(FunctionSignatureText.signature(in: "abc", functionStart: 10, bodyStart: nil))
        XCTAssertNil(FunctionSignatureText.signature(in: "abc", functionStart: 2, bodyStart: 2))
        XCTAssertNil(FunctionSignatureText.signature(in: "  \n ", functionStart: 0, bodyStart: nil))
    }

    // MARK: - With the real C++ grammar

    /// The signature of the function around the cursor, found the way ``ExpectedTypeService`` finds it:
    /// the innermost `function_definition` and its `body` field.
    private func signature(in source: String) throws -> String? {
        let parser = Parser()
        try parser.setLanguage(try XCTUnwrap(CodeLanguage.cpp.language))
        let text = source.replacingOccurrences(of: "|", with: "")
        let cursor = (source as NSString).range(of: "|").location
        let tree = try XCTUnwrap(parser.parse(text))
        var node = tree.rootNode?.descendant(in: UInt32(2 * cursor)..<UInt32(2 * cursor + 2))
        while let current = node, current.nodeType != "function_definition" { node = current.parent }
        guard let function = node else { return nil }
        return FunctionSignatureText.signature(
            in: text,
            functionStart: function.range.location,
            bodyStart: function.child(byFieldName: "body")?.range.location
        )
    }

    func testRealGrammarFindsTheHeaderOfAFreeFunction() throws {
        XCTAssertEqual(
            try signature(in: "int add(int a, int b)\n{\n    return a +| b;\n}\n"),
            "int add(int a, int b)"
        )
    }

    func testRealGrammarFindsTheHeaderOfAMemberFunctionDefinition() throws {
        XCTAssertEqual(
            try signature(in: "std::string Foo::name(const Bar& bar) const {\n    int x = 1;\n    |x;\n}\n"),
            "std::string Foo::name(const Bar& bar) const"
        )
    }

    /// Why the text scan exists: a lone half-typed word makes tree-sitter read the function as a declaration.
    func testRealGrammarLosesTheFunctionWhileAWordIsHalfTyped() throws {
        XCTAssertNil(try signature(in: "int f(int a) {\n    |ret\n}\n"))
        XCTAssertEqual(
            FunctionSignatureText.enclosing(in: "int f(int a) {\n    ret\n}\n", before: 19),
            "int f(int a)"
        )
    }

    func testRealGrammarGivesNothingOutsideAFunction() throws {
        XCTAssertNil(try signature(in: "int x = |1;\n"))
    }

    // MARK: - The text scan

    /// The header found for the cursor at the `|` of `source`.
    private func scanned(_ source: String) -> String? {
        let cursor = (source as NSString).range(of: "|").location
        return FunctionSignatureText.enclosing(in: source.replacingOccurrences(of: "|", with: ""), before: cursor)
    }

    func testScanFindsTheFunctionAroundAHalfTypedStatement() {
        XCTAssertEqual(scanned("void g()\n{\n    pri|\n}\n"), "void g()")
    }

    func testScanSkipsNestedControlBlocksAndLambdas() {
        let source = """
        int run(int n, const char* name) {
            if (n > 0) {
                for (int i = 0; i < n; ++i) {
                    auto f = [&](int x) { return x; };
                    while (true) {
                        pr|
        """
        XCTAssertEqual(scanned(source), "int run(int n, const char* name)")
    }

    func testScanReadsQualifiersQualifiedNamesAndTemplateLines() {
        XCTAssertEqual(
            scanned("std::string Foo::name(const Bar& bar) const noexcept {\n    |"),
            "std::string Foo::name(const Bar& bar) const noexcept"
        )
        XCTAssertEqual(
            scanned("template <typename T>\nT biggest(T a, T b) {\n    |"),
            "template <typename T> T biggest(T a, T b)"
        )
    }

    func testScanStopsAtThePreviousDeclaration() {
        let source = "#include <string>\nint a;\nvoid first() { }\nstatic int second(int v) {\n    |"
        XCTAssertEqual(scanned(source), "static int second(int v)")
    }

    func testScanIgnoresAccessLabelsAndLineComments() {
        let source = "class C {\npublic:\n    // adds\n    int add(int a) {\n        |"
        XCTAssertEqual(scanned(source), "int add(int a)")
    }

    func testScanFindsNothingAtFileScopeOrInAClassBody() {
        XCTAssertNil(scanned("int x = |"))
        XCTAssertNil(scanned("struct S {\n    int a;\n    |"))
        XCTAssertNil(scanned("namespace n {\n    |"))
        XCTAssertNil(scanned("void done() {\n}\n|"))
    }

    func testScanTakesTheInnermostFunctionOfALocalClass() {
        let source = "void outer() {\n    struct L {\n        int get() const {\n            |"
        XCTAssertEqual(scanned(source), "int get() const")
    }

    // MARK: - The enclosure for the return slot

    /// What the scan for the `return` slot finds at the `|` of `source`.
    private func enclosure(_ source: String) -> FunctionSignatureText.Enclosure? {
        let cursor = (source as NSString).range(of: "|").location
        return FunctionSignatureText.enclosure(in: source.replacingOccurrences(of: "|", with: ""), before: cursor)
    }

    func testEnclosureGivesTheDeclarationTextBeforeTheName() {
        XCTAssertEqual(enclosure("int f() {\n    ret|"), .function(returnText: "int"))
        XCTAssertEqual(
            enclosure("static std::string *Foo::g(int a) const {\n    |"),
            .function(returnText: "static std::string *")
        )
        XCTAssertEqual(enclosure("Widget::Widget() {\n    |"), .function(returnText: ""))
    }

    func testEnclosureSkipsControlBlocksButStopsAtLambdas() {
        XCTAssertEqual(
            enclosure("long f(int n) {\n    if (n) {\n        while (true) {\n            |"),
            .function(returnText: "long")
        )
        XCTAssertEqual(enclosure("int f() {\n    auto g = [](int x) {\n        |"), .opaque)
        XCTAssertEqual(enclosure("int f() {\n    auto g = [&] {\n        |"), .opaque)
        XCTAssertEqual(enclosure("int f() {\n    auto g = [n]() mutable {\n        |"), .opaque)
        XCTAssertEqual(enclosure("int f() {\n    auto g = [](int x) -> long {\n        |"), .opaque)
        XCTAssertEqual(enclosure("auto f() -> int {\n    |"), .opaque)
    }

    func testEnclosureIgnoresALambdaThatIsAlreadyClosed() {
        XCTAssertEqual(
            enclosure("int f() {\n    auto g = [](int x) { return x; };\n    |"),
            .function(returnText: "int")
        )
    }

    func testEnclosureFindsNothingOutsideAFunction() {
        XCTAssertNil(enclosure("int x = |"))
        XCTAssertNil(enclosure("namespace n {\n    |"))
    }
}
