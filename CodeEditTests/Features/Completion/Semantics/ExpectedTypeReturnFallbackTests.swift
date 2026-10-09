//
//  ExpectedTypeReturnFallbackTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
@testable import CodeEdit

/// The `return` slot while the syntax tree has no function around the cursor, as happens while the user
/// types: the resolver reads the declaration's text instead.
final class ExpectedTypeReturnFallbackTests: XCTestCase {
    /// Resolves the slot at the last `|` in `source`, with an environment whose tree knows nothing.
    private func resolve(_ source: String) async -> TypeText? {
        let marker = (source as NSString).range(of: "|", options: .backwards)
        let text = (source as NSString).replacingCharacters(in: marker, with: "")
        let string = text as NSString
        var prefixStart = marker.location
        while prefixStart > 0, let scalar = Unicode.Scalar(string.character(at: prefixStart - 1)),
              CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).contains(scalar) {
            prefixStart -= 1
        }
        return await ExpectedTypeResolver(environment: ExpectedTypeEnvironment()).resolve(
            text: text, prefixStart: prefixStart, cursor: marker.location, intent: .expression, languageId: "cpp"
        )
    }

    private func type(_ text: String) -> TypeText? { TypeText.parse(text) }

    func testReturnWithoutASyntaxTreeReadsTheDeclarationText() async {
        let slot = await resolve("int f() {\n    return pre|\n}")
        XCTAssertEqual(slot, type("int"))
    }

    func testReturnWithoutASyntaxTreeKeepsPointerStarsAndDropsQualifiers() async {
        let slot = await resolve("std::string *g() const {\n    return |\n}")
        XCTAssertEqual(slot, type("std::string*"))
        let reference = await resolve("const std::string &name() const {\n    return |\n}")
        XCTAssertEqual(reference, type("std::string"))
    }

    func testReturnWithoutASyntaxTreeSkipsSpecifiersTemplatesAndScopes() async {
        let specifiers = await resolve("static inline constexpr int f(int a) {\n    return |\n}")
        XCTAssertEqual(specifiers, type("int"))
        let template = await resolve("template <typename T, int N>\nT pick(T a) {\n    return |\n}")
        XCTAssertEqual(template, type("T"))
        let method = await resolve("Color Palette::primary() const noexcept {\n    return |\n}")
        XCTAssertEqual(method, type("Color"))
        let afterAnotherFunction = await resolve("void a() {}\nvirtual double b() { return |\n}")
        XCTAssertEqual(afterAnotherFunction, type("double"))
    }

    func testReturnWithoutASyntaxTreeInANestedBlockUsesTheFunction() async {
        let slot = await resolve("int f(int a) {\n    if (a > 0) {\n        for (;;) {\n            return |\n")
        XCTAssertEqual(slot, type("int"))
        let afterClosedBlock = await resolve("int f(int a) {\n    if (a) { g(); }\n    return |\n}")
        XCTAssertEqual(afterClosedBlock, type("int"))
    }

    func testReturnWithoutASyntaxTreeInAVoidFunctionExpectsNothing() async {
        let slot = await resolve("static void h() {\n    return |\n}")
        XCTAssertNil(slot)
        let pointer = await resolve("void *alloc() {\n    return |\n}")
        XCTAssertEqual(pointer, type("void*"))
    }

    func testReturnWithoutASyntaxTreeInALambdaExpectsNothing() async {
        let withParameters = await resolve("int f() {\n    auto g = [](int x) { return |\n}")
        XCTAssertNil(withParameters)
        let withoutParameters = await resolve("int f() {\n    auto g = [&] { return |\n}")
        XCTAssertNil(withoutParameters)
        let mutableLambda = await resolve("int f() {\n    auto g = [n]() mutable { return |\n}")
        XCTAssertNil(mutableLambda)
        let trailing = await resolve("int f() {\n    auto g = [](int x) -> long { return |\n}")
        XCTAssertNil(trailing)
    }

    func testReturnWithoutASyntaxTreeIgnoresUnreadableHeaders() async {
        let constructor = await resolve("Widget::Widget() {\n    return |\n}")
        XCTAssertNil(constructor)
        let deduced = await resolve("auto f() {\n    return |\n}")
        XCTAssertNil(deduced)
        let trailingReturnType = await resolve("auto f() -> int {\n    return |\n}")
        XCTAssertNil(trailingReturnType)
        let outsideAnyFunction = await resolve("return |")
        XCTAssertNil(outsideAnyFunction)
        let notAFunction = await resolve("x = foo(1) {\n    return |\n}")
        XCTAssertNil(notAFunction)
    }
}
