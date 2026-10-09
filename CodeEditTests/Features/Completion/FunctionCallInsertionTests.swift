//
//  FunctionCallInsertionTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
@testable import CodeEdit

final class FunctionCallInsertionTests: XCTestCase {
    func testSignatureInTheLabelWithParametersPutsTheCaretInside() {
        let result = FunctionCallInsertion.insertion(label: " foo(int a, int b)", detail: "int", nextCharacter: nil)
        XCTAssertEqual(result, .init(text: "()", caretOffset: 1))
    }

    func testEmptyOrVoidSignatureLeavesTheCaretAfterTheParentheses() {
        XCTAssertEqual(
            FunctionCallInsertion.insertion(label: "size()", detail: "size_t", nextCharacter: nil)?.caretOffset,
            2
        )
        XCTAssertEqual(
            FunctionCallInsertion.insertion(label: "init(void)", detail: nil, nextCharacter: nil)?.caretOffset,
            2
        )
    }

    func testSignatureIsReadFromDetailWhenTheLabelIsOnlyAName() {
        XCTAssertEqual(
            FunctionCallInsertion.insertion(label: "push_back", detail: "void (const T &)", nextCharacter: nil)?
                .caretOffset,
            1
        )
        XCTAssertEqual(
            FunctionCallInsertion.insertion(label: "empty", detail: "bool ()", nextCharacter: nil)?.caretOffset,
            2
        )
    }

    func testUnparsableSignatureFallsBackToCaretBetweenTheParentheses() {
        let result = FunctionCallInsertion.insertion(label: "foo", detail: "int", nextCharacter: nil)
        XCTAssertEqual(result, .init(text: "()", caretOffset: 1))
    }

    func testNestedParenthesesInParametersAreBalanced() {
        XCTAssertEqual(FunctionCallInsertion.parameters(in: "run(void (*cb)(int))"), true)
        XCTAssertEqual(FunctionCallInsertion.parameters(in: "run()"), false)
        XCTAssertNil(FunctionCallInsertion.parameters(in: "run(int"))
    }

    func testAnExistingOpeningParenthesisSuppressesTheInsertion() {
        XCTAssertNil(FunctionCallInsertion.insertion(label: "foo(int)", detail: nil, nextCharacter: "("))
    }

    func testOperatorsAreLeftAlone() {
        XCTAssertNil(FunctionCallInsertion.insertion(label: "operator()", detail: nil, nextCharacter: nil))
    }

    func testLeadingIncludeMarkerAndPaddingAreIgnored() {
        XCTAssertEqual(
            FunctionCallInsertion.insertion(label: "•getenv(const char *)", detail: nil, nextCharacter: nil)?
                .caretOffset,
            1
        )
    }
}
