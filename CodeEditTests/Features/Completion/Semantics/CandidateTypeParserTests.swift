//
//  CandidateTypeParserTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
import LanguageServerProtocol
@testable import CodeEdit

final class CandidateTypeParserTests: XCTestCase {
    private func candidate(
        _ label: String,
        kind: LSPCompletionCategory,
        detail: String?,
        source: CompletionSource = .lsp
    ) -> CompletionCandidate {
        CompletionCandidate(
            id: UUID().uuidString,
            label: label,
            filterText: label,
            kind: kind,
            source: source,
            detail: detail,
            payload: .plain(insertText: label)
        )
    }

    func testAFunctionHasItsReturnType() {
        let result = CandidateTypeParser.resultType(of: candidate(" count_items", kind: .function, detail: "int"))
        XCTAssertEqual(result, TypeText(name: "int"))
    }

    func testAVariableHasItsType() {
        let result = CandidateTypeParser.resultType(
            of: candidate(" name", kind: .variable, detail: "const std::string &")
        )
        XCTAssertEqual(result, TypeText(name: "std::string"))
    }

    func testAnEnumeratorHasItsEnum() {
        let result = CandidateTypeParser.resultType(of: candidate(" Red", kind: .enumMember, detail: "Color"))
        XCTAssertEqual(result, TypeText(name: "Color"))
    }

    func testAPointerVariableKeepsItsDepth() {
        let result = CandidateTypeParser.resultType(of: candidate(" head", kind: .variable, detail: "Node *"))
        XCTAssertEqual(result, TypeText(name: "Node", pointerDepth: 1))
    }

    func testClangdsSpellingOfStdStringIsRecognized() {
        let item = candidate(" s", kind: .function, detail: "basic_string<char>")
        let result = CandidateTypeParser.resultType(of: item)
        XCTAssertEqual(result, TypeText(name: "std::string"))
    }

    func testTypesAndNamespacesHaveNoResultType() {
        for kind in [LSPCompletionCategory.class, .struct, .enum, .typeAlias, .namespace, .interface] {
            XCTAssertNil(
                CandidateTypeParser.resultType(of: candidate(" Point", kind: kind, detail: "Point")),
                "\(kind) must not be given a value type"
            )
        }
    }

    func testItemsWithoutADetailHaveNoResultType() {
        XCTAssertNil(CandidateTypeParser.resultType(of: candidate(" Point", kind: .function, detail: nil)))
        XCTAssertNil(CandidateTypeParser.resultType(of: candidate(" f", kind: .function, detail: "")))
    }

    func testOtherSourcesAndNonTypeDetailsAreIgnored() {
        let fromWords = candidate("count", kind: .variable, detail: "int", source: .word)
        XCTAssertNil(CandidateTypeParser.resultType(of: fromWords))
        let include = candidate("#include <x>", kind: .snippet, detail: "Include system header")
        XCTAssertNil(CandidateTypeParser.resultType(of: include))
        let prose = candidate("if", kind: .snippet, detail: "Control flow with a long text")
        XCTAssertNil(CandidateTypeParser.resultType(of: prose))
    }

    func testNullptrKeywordFromClangdIsANullPointerType() {
        let item = candidate(" nullptr", kind: .snippet, detail: "std::nullptr_t")
        let result = CandidateTypeParser.resultType(of: item)
        XCTAssertEqual(result, TypeText(name: "std::nullptr_t"))
    }

    func testOnlyTheFirstLineOfDetailIsRead() {
        let result = CandidateTypeParser.resultType(of: candidate("f", kind: .function, detail: "int\nextra"))
        XCTAssertEqual(result, TypeText(name: "int"))
    }
}

final class LSPTypeExtractionTests: XCTestCase {
    func testHoverTypeLineIsRead() {
        let hover = "variable v\n\nType: std::vector<int>\n\n// In main\nstd::vector<int> v"
        XCTAssertEqual(LSPTypeExtraction.type(fromHover: hover), TypeText(name: "std::vector<int>"))
    }

    func testHoverTypeInMarkdownIsRead() {
        let point = LSPTypeExtraction.type(fromHover: "### variable `p`\n\nType: `Point`")
        XCTAssertEqual(point, TypeText(name: "Point"))
        let text = LSPTypeExtraction.type(fromHover: "- Type: `const char *`")
        XCTAssertEqual(text, TypeText(name: "char", pointerDepth: 1))
    }

    func testHoverOverAFunctionUsesTheReturnType() {
        XCTAssertEqual(
            LSPTypeExtraction.type(fromHover: "function kind\n\n→ Color\nParameters:\n- int n"),
            TypeText(name: "Color")
        )
        XCTAssertEqual(LSPTypeExtraction.type(fromHover: "function f\n\nReturns: `int`"), TypeText(name: "int"))
    }

    func testHoverWithoutATypeYieldsNothing() {
        XCTAssertNil(LSPTypeExtraction.type(fromHover: "namespace std"))
        XCTAssertNil(LSPTypeExtraction.type(fromHover: ""))
    }

    func testParameterTypeDropsTheName() {
        let cases: [(String, TypeText)] = [
            ("const std::string &name", TypeText(name: "std::string")),
            ("int n", TypeText(name: "int")),
            ("int", TypeText(name: "int")),
            ("Point p", TypeText(name: "Point")),
            ("char *argv", TypeText(name: "char", pointerDepth: 1)),
            ("const Point", TypeText(name: "Point")),
            ("std::string", TypeText(name: "std::string")),
            ("std::vector<int> v", TypeText(name: "std::vector<int>")),
            ("unsigned int", TypeText(name: "unsigned int")),
            ("unsigned count", TypeText(name: "unsigned int")),
            ("size_t len = 0", TypeText(name: "size_t")),
            ("const char *", TypeText(name: "char", pointerDepth: 1)),
            ("std::vector<int> &", TypeText(name: "std::vector<int>"))
        ]
        for (label, expected) in cases {
            XCTAssertEqual(LSPTypeExtraction.parameterType(fromLabel: label), expected, "label `\(label)`")
        }
    }

    func testActiveParameterTypeComesFromTheActiveSignature() {
        let signature = SignatureInformation(
            label: "count_items(const std::string &name, int n) -> int",
            parameters: [
                ParameterInformation(label: .optionA("const std::string &name")),
                ParameterInformation(label: .optionA("int n"))
            ]
        )
        let first = SignatureHelp(signatures: [signature], activeSignature: 0, activeParameter: 0)
        let second = SignatureHelp(signatures: [signature], activeSignature: 0, activeParameter: 1)
        XCTAssertEqual(LSPTypeExtraction.activeParameterType(in: first), TypeText(name: "std::string"))
        XCTAssertEqual(LSPTypeExtraction.activeParameterType(in: second), TypeText(name: "int"))
        XCTAssertNil(LSPTypeExtraction.activeParameterType(in: SignatureHelp(signatures: [])))
        let beyond = SignatureHelp(signatures: [signature], activeSignature: 0, activeParameter: 5)
        XCTAssertNil(LSPTypeExtraction.activeParameterType(in: beyond))
    }

    func testActiveParameterTypeUnderstandsOffsetLabels() {
        let label = "f(int a, double b)"
        let signature = SignatureInformation(
            label: label,
            parameters: [
                ParameterInformation(label: .optionB([2, 7])),
                ParameterInformation(label: .optionB([9, 17]))
            ]
        )
        let help = SignatureHelp(signatures: [signature], activeSignature: 0, activeParameter: 1)
        XCTAssertEqual(LSPTypeExtraction.activeParameterType(in: help), TypeText(name: "double"))
    }
}
