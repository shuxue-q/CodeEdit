//
//  ExpectedTypeResolverTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
@testable import CodeEdit

final class ExpectedTypeResolverTests: XCTestCase {
    /// What the doubles saw, to assert on which questions were asked.
    private final class Recorder {
        var hoveredSymbols: [String] = []
        var signatureRequests: [Int] = []
    }

    /// Resolves the slot at the last `|` in `source`. The word before the `|` is the typed prefix.
    private func resolve(
        _ source: String,
        intent: CompletionIntent = .expression,
        languageId: String = "cpp",
        symbolTypes: [String: String] = [:],
        parameterType: String? = nil,
        nodeTypes: [String] = [],
        returnTypeText: (type: String, declarator: String)? = nil,
        recorder: Recorder = Recorder()
    ) async -> TypeText? {
        let marker = (source as NSString).range(of: "|", options: .backwards)
        let cursor = marker.location
        let text = (source as NSString).replacingCharacters(in: marker, with: "")
        let string = text as NSString
        var prefixStart = cursor
        while prefixStart > 0, let scalar = Unicode.Scalar(string.character(at: prefixStart - 1)),
              CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).contains(scalar) {
            prefixStart -= 1
        }
        var environment = ExpectedTypeEnvironment()
        environment.nodeTypesAt = { _ in nodeTypes }
        environment.typeOfSymbol = { offset in
            var end = offset
            while end < string.length, let scalar = Unicode.Scalar(string.character(at: end)),
                  CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).contains(scalar) {
                end += 1
            }
            let symbol = string.substring(with: NSRange(location: offset, length: end - offset))
            recorder.hoveredSymbols.append(symbol)
            return symbolTypes[symbol].flatMap(TypeText.parse)
        }
        environment.activeParameterType = { offset in
            recorder.signatureRequests.append(offset)
            return parameterType.flatMap(TypeText.parse)
        }
        if let returnTypeText {
            environment.fieldRange = { _, ancestor, field in
                guard ancestor == "function_definition" else { return nil }
                let needle = field == "type" ? returnTypeText.type : returnTypeText.declarator
                let range = string.range(of: needle)
                return range.location == NSNotFound ? nil : range
            }
        }
        return await ExpectedTypeResolver(environment: environment).resolve(
            text: text, prefixStart: prefixStart, cursor: cursor, intent: intent, languageId: languageId
        )
    }

    private func type(_ text: String) -> TypeText? { TypeText.parse(text) }

    // MARK: - Declarations and assignments

    func testDeclarationInitializerExpectsTheDeclaredType() async {
        let slot = await resolve("void f() {\n    std::string s = |\n}")
        XCTAssertEqual(slot, type("std::string"))
    }

    func testDeclarationWithQualifiersPointersAndTemplates() async {
        let constRef = await resolve("const std::string &s = |")
        XCTAssertEqual(constRef, type("std::string"))
        let pointer = await resolve("    char *p = |")
        XCTAssertEqual(pointer, type("char*"))
        let templated = await resolve("    std::map<int, std::string> m = |")
        XCTAssertEqual(templated, type("std::map<int,std::string>"))
        let unsigned = await resolve("    unsigned long total = |")
        XCTAssertEqual(unsigned, type("unsigned long"))
        let staticInt = await resolve("    static const int limit = |")
        XCTAssertEqual(staticInt, type("int"))
    }

    func testDeclarationAfterAnotherStatementOnTheLine() async {
        let slot = await resolve("    int a = 1; double d = |")
        XCTAssertEqual(slot, type("double"))
    }

    func testAutoDeclarationExpectsNothing() async {
        let slot = await resolve("    auto x = |")
        XCTAssertNil(slot)
    }

    func testAssignmentAsksHoverForTheTypeOfTheTarget() async {
        let recorder = Recorder()
        let slot = await resolve(
            "    total = |", symbolTypes: ["total": "double"], recorder: recorder
        )
        XCTAssertEqual(slot, type("double"))
        XCTAssertEqual(recorder.hoveredSymbols, ["total"])
    }

    func testAssignmentToAMemberHoversTheLastName() async {
        let recorder = Recorder()
        let slot = await resolve(
            "    node->name = |", symbolTypes: ["name": "std::string"], recorder: recorder
        )
        XCTAssertEqual(slot, type("std::string"))
        XCTAssertEqual(recorder.hoveredSymbols, ["name"])
    }

    func testAssignmentWithoutHoverAnswerExpectsNothing() async {
        let slot = await resolve("    total = |")
        XCTAssertNil(slot)
    }

    func testComparisonsAndCompoundAssignmentsAreNotInitializers() async {
        let recorder = Recorder()
        let equal = await resolve("    if (a == |", symbolTypes: ["a": "int"], recorder: recorder)
        XCTAssertNil(equal)
        let lessEqual = await resolve("    ok = a <= |", symbolTypes: ["a": "int"], recorder: recorder)
        XCTAssertNil(lessEqual)
        XCTAssertTrue(recorder.hoveredSymbols.isEmpty)
    }

    func testMemberAccessOnTheRightHandSideStillSeesTheSlot() async {
        let slot = await resolve("    std::string s = p.|", intent: .memberAccess)
        XCTAssertEqual(slot, type("std::string"))
        let scope = await resolve("    int n = Limits::|", intent: .scopeAccess)
        XCTAssertEqual(scope, type("int"))
    }

    // MARK: - Return

    func testReturnExpectsTheFunctionsReturnType() async {
        let slot = await resolve(
            "std::string name() {\n    return |\n}",
            nodeTypes: ["return_statement", "compound_statement", "function_definition"],
            returnTypeText: (type: "std::string", declarator: "name()")
        )
        XCTAssertEqual(slot, type("std::string"))
    }

    func testReturnKeepsThePointerStarsOfTheDeclarator() async {
        let slot = await resolve(
            "const char *name() {\n    return |\n}",
            nodeTypes: ["compound_statement", "function_definition"],
            returnTypeText: (type: "const char", declarator: "*name()")
        )
        XCTAssertEqual(slot, type("char*"))
    }

    func testReturnInAVoidFunctionExpectsNothing() async {
        let slot = await resolve(
            "void run() {\n    return |\n}",
            nodeTypes: ["compound_statement", "function_definition"],
            returnTypeText: (type: "void", declarator: "run()")
        )
        XCTAssertNil(slot)
    }

    func testReturnInsideALambdaDoesNotUseTheOuterFunction() async {
        let slot = await resolve(
            "int f() {\n    auto g = [] { return |\n}",
            nodeTypes: ["compound_statement", "lambda_expression", "compound_statement", "function_definition"],
            returnTypeText: (type: "int", declarator: "f()")
        )
        XCTAssertNil(slot)
    }

    // MARK: - Calls

    func testCallArgumentUsesTheActiveParameterOfSignatureHelp() async {
        let recorder = Recorder()
        let first = await resolve("    count_items(|", parameterType: "std::string", recorder: recorder)
        XCTAssertEqual(first, type("std::string"))
        let second = await resolve("    count_items(name, |", parameterType: "int", recorder: recorder)
        XCTAssertEqual(second, type("int"))
        XCTAssertEqual(recorder.signatureRequests.count, 2)
    }

    func testSignatureHelpIsRequestedAtTheCursor() async {
        let recorder = Recorder()
        _ = await resolve("    f(a, b|", parameterType: "int", recorder: recorder)
        XCTAssertEqual(recorder.signatureRequests, [("    f(a, b" as NSString).length])
    }

    func testNestedCallUsesTheInnermostCall() async {
        let recorder = Recorder()
        let slot = await resolve("    outer(first(1, 2), inner(|", parameterType: "Point", recorder: recorder)
        XCTAssertEqual(slot, type("Point"))
    }

    func testCommaOutsideAnArgumentListExpectsNothing() async {
        let slot = await resolve("    int a, |", parameterType: "int")
        XCTAssertNil(slot)
        let braces = await resolve("    int v[] = {1, |", parameterType: "int")
        XCTAssertNil(braces)
    }

    func testMultiLineCallStillFindsTheCall() async {
        let slot = await resolve("    draw(point,\n         |", parameterType: "Color")
        XCTAssertEqual(slot, type("Color"))
    }

    func testTypeNameBeforeParenthesisFallsBackToTheType() async {
        let slot = await resolve("    Widget(|", nodeTypes: ["type_identifier", "call_expression"])
        XCTAssertEqual(slot, type("Widget"))
        let unknown = await resolve("    widget(|", nodeTypes: ["identifier", "call_expression"])
        XCTAssertNil(unknown)
    }

    func testBraceInitializerOfATypeExpectsThatType() async {
        let slot = await resolve("    return Point{|", nodeTypes: ["type_identifier"])
        XCTAssertEqual(slot, type("Point"))
        let notAType = await resolve("    std::string s{|", nodeTypes: ["identifier"])
        XCTAssertNil(notAType)
    }

    // MARK: - Conditions and case labels

    func testConditionsExpectBool() async {
        let bool = type("bool")
        let ifSlot = await resolve("    if (|")
        XCTAssertEqual(ifSlot, bool)
        let whileSlot = await resolve("    while (|")
        XCTAssertEqual(whileSlot, bool)
        let not = await resolve("    ok = !|")
        XCTAssertEqual(not, bool)
        let and = await resolve("    if (a && |")
        XCTAssertEqual(and, bool)
        let either = await resolve("    if (a || |")
        XCTAssertEqual(either, bool)
        let elseIf = await resolve("    } else if (|")
        XCTAssertEqual(elseIf, bool)
    }

    func testOtherParenthesesExpectNothing() async {
        let forSlot = await resolve("    for (|", parameterType: "int")
        XCTAssertNil(forSlot)
        let sizeofSlot = await resolve("    sizeof(|", parameterType: "int")
        XCTAssertNil(sizeofSlot)
    }

    func testCaseExpectsTheTypeOfTheSwitchCondition() async {
        let recorder = Recorder()
        let source = "    switch (mode) {\n    case |"
        let slot = await resolve(source, intent: .caseLabel, symbolTypes: ["mode": "Mode"], recorder: recorder)
        XCTAssertEqual(slot, type("Mode"))
        XCTAssertEqual(recorder.hoveredSymbols, ["mode"])
    }

    func testCaseAfterEarlierCasesStillFindsTheSwitch() async {
        let source = "    switch (shape.kind) {\n    case Circle: { f(); break; }\n    case |"
        let slot = await resolve(source, intent: .caseLabel, symbolTypes: ["kind": "Kind"])
        XCTAssertEqual(slot, type("Kind"))
    }

    func testCaseOutsideASwitchExpectsNothing() async {
        let slot = await resolve("    case |", intent: .caseLabel, symbolTypes: ["mode": "Mode"])
        XCTAssertNil(slot)
    }

    // MARK: - Gating

    func testOnlyCFamilyLanguagesAreResolved() async {
        let python = await resolve("    x = |", languageId: "python", symbolTypes: ["x": "int"])
        XCTAssertNil(python)
        let cmake = await resolve("    if (|", languageId: "cmake")
        XCTAssertNil(cmake)
        let cLanguage = await resolve("    int x = |", languageId: "c")
        XCTAssertEqual(cLanguage, type("int"))
    }

    func testIntentsWithoutAValueSlotAreSkipped() async {
        let statement = await resolve("    int x = |", intent: .statement)
        XCTAssertNil(statement)
        let typeName = await resolve("    int x = |", intent: .typeName)
        XCTAssertNil(typeName)
        let comment = await resolve("    int x = |", intent: .comment)
        XCTAssertNil(comment)
    }

    func testNoSlotAtTheStartOfTheDocumentOrAfterANonSlotToken() async {
        let start = await resolve("|")
        XCTAssertNil(start)
        let plus = await resolve("    a + |", parameterType: "int")
        XCTAssertNil(plus)
        let declarationName = await resolve("    int |")
        XCTAssertNil(declarationName)
    }
}
