//
//  PostfixCompletionProviderTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
import CodeEditLanguages
@testable import CodeEditSourceEditor
import SwiftTreeSitter
@testable import CodeEdit

@MainActor
final class PostfixCompletionProviderTests: XCTestCase {
    /// Parses `source` as C++ with the real grammar.
    private func tree(_ source: String) throws -> MutableTree {
        let parser = Parser()
        try parser.setLanguage(try XCTUnwrap(CodeLanguage.cpp.language))
        return try XCTUnwrap(parser.parse(source))
    }

    /// The expression the finder reports for the `.` that follows `marker`'s last occurrence.
    private func expression(in source: String, endingBefore dotMarker: String = ".|") throws -> String? {
        let dot = (source as NSString).range(of: dotMarker, options: .backwards).location
        let text = source.replacingOccurrences(of: "|", with: "")
        let tree = try tree(text)
        let root = try XCTUnwrap(tree.rootNode)
        guard dot > 0, let leaf = root.descendant(in: UInt32(2 * (dot - 1))..<UInt32(2 * dot)) else { return nil }
        guard let range = PostfixExpressionFinder.range(endingAt: dot, in: [leaf]) else { return nil }
        return (text as NSString).substring(with: range)
    }

    // MARK: - Finding the expression with the real C++ grammar

    func testIdentifierBeforeADot() throws {
        XCTAssertEqual(try expression(in: "void f() {\n    ok.|\n}"), "ok")
    }

    func testCallBeforeADot() throws {
        XCTAssertEqual(try expression(in: "void f() {\n    make(1, 2).|\n}"), "make(1, 2)")
    }

    func testMemberChainBeforeADot() throws {
        XCTAssertEqual(try expression(in: "void f() {\n    a.b->c.|\n}"), "a.b->c")
    }

    func testSubscriptAndParenthesizedAndLiterals() throws {
        XCTAssertEqual(try expression(in: "void f() {\n    values[i].|\n}"), "values[i]")
        XCTAssertEqual(try expression(in: "void f() {\n    (a + b).|\n}"), "(a + b)")
        XCTAssertEqual(try expression(in: "void f() {\n    \"text\".|\n}"), "\"text\"")
    }

    func testOnlyTheOperandBindsToTheDot() throws {
        XCTAssertEqual(try expression(in: "void f() {\n    x = a + b.|\n}"), "b")
        XCTAssertEqual(try expression(in: "void f() {\n    if (!ok.|\n}"), "ok")
    }

    func testIncompleteStatementFollowedByCode() throws {
        XCTAssertEqual(try expression(in: "void f() {\n    items.|\n    int y = 1;\n}"), "items")
    }

    func testNoExpressionBeforeADotAtTheStartOfAStatement() throws {
        XCTAssertNil(try expression(in: "void f() {\n    .|\n}"))
    }

    // MARK: - Provider

    private func context(
        _ source: String,
        intent: CompletionIntent = .memberAccess,
        languageId: String = "cpp"
    ) -> CompletionContext {
        let cursor = (source as NSString).range(of: "|").location
        let text = source.replacingOccurrences(of: "|", with: "")
        let string = text as NSString
        var start = cursor
        while start > 0, let scalar = Unicode.Scalar(string.character(at: start - 1)),
              CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).contains(scalar) {
            start -= 1
        }
        return CompletionContext(
            prefix: string.substring(with: NSRange(location: start, length: cursor - start)),
            prefixRange: NSRange(location: start, length: cursor - start),
            triggerCharacter: ".",
            intent: intent,
            languageId: languageId,
            documentText: text,
            cursorOffset: cursor,
            expectedType: nil
        )
    }

    /// A provider whose expression is the identifier chain right before the dot.
    private func provider(typeNameAt: Int? = nil) -> PostfixCompletionProvider {
        PostfixCompletionProvider(
            expressionRange: { dot in
                // Walk back over identifier characters and member operators.
                let chars = Array("\(self.currentText)".utf16)
                var start = dot
                while start > 0, let scalar = Unicode.Scalar(chars[start - 1]),
                      CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.>-")).contains(scalar) {
                    start -= 1
                }
                return start < dot ? NSRange(location: start, length: dot - start) : nil
            },
            nodeTypesAt: { _ in typeNameAt == nil ? [] : ["type_identifier"] }
        )
    }

    private var currentText = ""

    private func candidates(
        _ source: String,
        intent: CompletionIntent = .memberAccess,
        languageId: String = "cpp",
        provider: PostfixCompletionProvider? = nil
    ) -> [CompletionCandidate] {
        let context = context(source, intent: intent, languageId: languageId)
        currentText = context.documentText
        return (provider ?? self.provider()).candidates(for: context)
    }

    func testOffersTheTemplatesAfterADot() {
        let result = candidates("void f() {\n    ok.|\n}")
        XCTAssertEqual(result.first?.label, "if")
        XCTAssertTrue(result.allSatisfy { $0.source == .postfix })
        XCTAssertEqual(result.first?.detail, "if (ok) {…}")
        guard case .snippet(let body)? = result.first?.payload else { return XCTFail("Expected a snippet payload") }
        XCTAssertEqual(body, "if (ok) {\n\t$0\n}")
    }

    func testTheTypedPrefixDoesNotChangeTheOffer() {
        let result = candidates("void f() {\n    ok.fo|\n}")
        XCTAssertTrue(result.map(\.label).contains("fori"))
    }

    func testNothingAfterAnArrowOrScopeOperator() {
        XCTAssertTrue(candidates("void f() {\n    node->|\n}").isEmpty)
        XCTAssertTrue(candidates("void f() {\n    std::|\n}").isEmpty)
    }

    func testOnlyMemberAccessIntentGetsTemplates() {
        XCTAssertTrue(candidates("void f() {\n    ok.|\n}", intent: .expression).isEmpty)
        XCTAssertTrue(candidates("void f() {\n    ok.|\n}", intent: .statement).isEmpty)
    }

    func testNothingForOtherLanguages() {
        XCTAssertTrue(candidates("ok.|", languageId: "python").isEmpty)
    }

    func testNothingWhenNoNodeEndsBeforeTheDot() {
        let empty = PostfixCompletionProvider(expressionRange: { _ in nil })
        XCTAssertTrue(candidates("void f() {\n    ok.|\n}", provider: empty).isEmpty)
    }

    func testNewNeedsATypeName() {
        let plain = candidates("void f() {\n    widget.|\n}")
        XCTAssertFalse(plain.map(\.label).contains("new"))
        let typed = candidates("void f() {\n    Widget.|\n}")
        XCTAssertTrue(typed.map(\.label).contains("new"), "Capitalized names count as types")
    }

    func testCandidatesHaveStableIdsAndTheMemberAccessWeight() {
        let result = candidates("void f() {\n    ok.|\n}")
        XCTAssertEqual(result.first?.id, "postfix.if")
        XCTAssertEqual(
            CompletionIntentPolicy.weight(kind: .snippet, source: .postfix, intent: .memberAccess, isExplicit: false),
            0.6
        )
        for intent in CompletionIntent.allCases where intent != .memberAccess {
            XCTAssertNil(
                CompletionIntentPolicy.weight(kind: .snippet, source: .postfix, intent: intent, isExplicit: true),
                "Postfix templates must be excluded in \(intent)"
            )
        }
    }

    // MARK: - Ranking

    private func ranked(_ source: String, members: [String]) -> [String] {
        let context = context(source)
        currentText = context.documentText
        let postfix = provider().candidates(for: context)
        let lsp = members.enumerated().map { index, name in
            CompletionCandidate(
                id: "lsp.\(name)", label: name, filterText: name, sortText: String(format: "4%03d", index),
                kind: .function, source: .lsp, payload: .plain(insertText: name)
            )
        }
        return CompletionRanker.rank(
            lsp + postfix, prefix: context.prefix, intent: .memberAccess
        ).items.map(\.label)
    }

    func testATemplateTypedInFullOutranksMembers() {
        let result = ranked("void f() {\n    v.for|\n}", members: ["format", "forward", "front"])
        XCTAssertEqual(result.first, "for", "Got \(result)")
    }

    func testAPartiallyTypedTemplateSitsBelowTheMatchingMembers() {
        let result = ranked("void f() {\n    v.fo|\n}", members: ["format", "forward"])
        XCTAssertEqual(Array(result.prefix(2)), ["format", "forward"], "Got \(result)")
        XCTAssertTrue(result.contains("for"))
        XCTAssertTrue(result.contains("fori"))
    }

    func testWithoutAPrefixMembersComeBeforeTemplates() {
        let result = ranked("void f() {\n    v.|\n}", members: ["begin", "end"])
        XCTAssertEqual(Array(result.prefix(2)), ["begin", "end"], "Got \(result)")
    }
}
