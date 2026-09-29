//
//  LSPSignatureHelpTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/29/26.
//

import Foundation
import LanguageServerProtocol
import Testing

@testable import CodeEdit

@MainActor
struct LSPSignatureHelpTests {
    @Test
    func offsetLabelsSelectTheActiveParameter() throws {
        let help = SignatureHelp(
            signatures: [
                SignatureInformation(
                    label: "const Ep *begin(initializer_list<Ep> il)",
                    parameters: [ParameterInformation(label: .optionB([16, 39]))]
                )
            ],
            activeSignature: 0,
            activeParameter: 0
        )
        let content = try #require(LSPSignatureHelpContent(help: help))
        #expect(content.activeParameterRange == NSRange(location: 16, length: 23))
        #expect(content.signatureCount == 1)
    }

    @Test
    func stringLabelsResolveInOrderAfterTheParenthesis() throws {
        let help = SignatureHelp(
            signatures: [
                SignatureInformation(label: "int f(int, int)"),
                SignatureInformation(
                    label: "int max(int, int)",
                    documentation: nil,
                    parameters: [
                        ParameterInformation(label: .optionA("int")),
                        ParameterInformation(label: .optionA("int"), documentation: .optionA("  the second  "))
                    ],
                    activeParameter: 1
                )
            ],
            activeSignature: 1,
            activeParameter: 0
        )
        let content = try #require(LSPSignatureHelpContent(help: help))
        // The signature's own activeParameter wins over the response-level one.
        #expect(content.activeParameterRange == NSRange(location: 13, length: 3))
        #expect(content.parameterDocumentation == "the second")
        #expect(content.signatureIndex == 1)
        #expect(content.signatureCount == 2)
    }

    @Test
    func emptyResponseShowsNothing() {
        #expect(LSPSignatureHelpContent(help: SignatureHelp(signatures: [])) == nil)
    }

    @Test
    func callStartFindsTheInnermostOpenCall() {
        let text = "x = std::begin(foo(a), b" as NSString
        #expect(LSPSignatureHelpCoordinator.callStart(before: text.length, in: text) == 4)
        let inner = "x = outer(inner(a" as NSString
        #expect(LSPSignatureHelpCoordinator.callStart(before: inner.length, in: inner) == 10)
        let closed = "f(a); g" as NSString
        #expect(LSPSignatureHelpCoordinator.callStart(before: closed.length, in: closed) == nil)
    }
}
