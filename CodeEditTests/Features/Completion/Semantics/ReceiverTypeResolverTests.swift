//
//  ReceiverTypeResolverTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
@testable import CodeEdit

final class ReceiverTypeResolverTests: XCTestCase {
    /// Resolves the receiver at the last `|` in `source`; the hover answers by the symbol at the offset.
    private func resolve(
        _ source: String,
        intent: CompletionIntent = .memberAccess,
        languageId: String = "cpp",
        symbolTypes: [String: String] = [:],
        hovered: UnsafeMutablePointer<[String]>? = nil
    ) async -> String? {
        let marker = (source as NSString).range(of: "|", options: .backwards)
        let text = (source as NSString).replacingCharacters(in: marker, with: "")
        let string = text as NSString
        var prefixStart = marker.location
        while prefixStart > 0, let scalar = Unicode.Scalar(string.character(at: prefixStart - 1)),
              CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).contains(scalar) {
            prefixStart -= 1
        }
        var seen: [String] = []
        let resolver = ReceiverTypeResolver { offset in
            var end = offset
            while end < string.length, let scalar = Unicode.Scalar(string.character(at: end)),
                  CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).contains(scalar) {
                end += 1
            }
            let symbol = string.substring(with: NSRange(location: offset, length: end - offset))
            seen.append(symbol)
            return symbolTypes[symbol].flatMap(TypeText.parse)
        }
        let result = await resolver.resolve(
            text: text, prefixStart: prefixStart, intent: intent, languageId: languageId
        )
        hovered?.pointee = seen
        return result
    }

    func testTheTypeOfAVariableBeforeADot() async {
        let result = await resolve("    v.|", symbolTypes: ["v": "std::vector<int>"])
        XCTAssertEqual(result, "std::vector<int>")
    }

    func testTheTypedPrefixIsNotPartOfTheReceiver() async {
        let result = await resolve("    v.push_|", symbolTypes: ["v": "std::vector<int>", "push_": "Wrong"])
        XCTAssertEqual(result, "std::vector<int>")
    }

    func testAnArrowGivesThePointeeType() async {
        let result = await resolve("    node->|", symbolTypes: ["node": "const Node *"])
        XCTAssertEqual(result, "Node")
    }

    func testQualifiersAndReferencesAreNormalizedAway() async {
        let result = await resolve("    s.|", symbolTypes: ["s": "const std::string &"])
        XCTAssertEqual(result, "std::string")
    }

    func testAMemberChainHoversTheLastMember() async {
        var hovered: [String] = []
        let result = await resolve("    owner.items.|", symbolTypes: ["items": "std::vector<int>"], hovered: &hovered)
        XCTAssertEqual(result, "std::vector<int>")
        XCTAssertEqual(hovered, ["items"])
    }

    func testACallHoversTheCalledFunctionForItsReturnType() async {
        var hovered: [String] = []
        let result = await resolve("    make(1, f(2)).|", symbolTypes: ["make": "Widget"], hovered: &hovered)
        XCTAssertEqual(result, "Widget")
        XCTAssertEqual(hovered, ["make"])
    }

    func testReceiversTheHoverCannotTypeGiveNothing() async {
        let unknown = await resolve("    v.|")
        XCTAssertNil(unknown)
        let subscripted = await resolve("    v[0].|", symbolTypes: ["v": "std::vector<int>"])
        XCTAssertNil(subscripted)
        let parenthesized = await resolve("    (a + b).|", symbolTypes: ["a": "int"])
        XCTAssertNil(parenthesized)
        let literal = await resolve("    \"text\".|")
        XCTAssertNil(literal)
    }

    func testNoReceiverAfterAScopeOperatorOrOutsideMemberAccess() async {
        let scope = await resolve("    std::|", symbolTypes: ["std": "X"])
        XCTAssertNil(scope)
        let wrongIntent = await resolve("    v.|", intent: .expression, symbolTypes: ["v": "Widget"])
        XCTAssertNil(wrongIntent)
        let wrongLanguage = await resolve("    v.|", languageId: "python", symbolTypes: ["v": "Widget"])
        XCTAssertNil(wrongLanguage)
        let nothingBefore = await resolve(".|", symbolTypes: ["v": "Widget"])
        XCTAssertNil(nothingBefore)
    }
}
