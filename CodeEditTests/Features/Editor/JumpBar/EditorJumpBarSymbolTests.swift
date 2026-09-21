//
//  EditorJumpBarSymbolTests.swift
//  CodeEditTests
//
//  Created by CodeEdit on 9/17/26.
//

import XCTest
import LanguageServerProtocol
import CodeEditSourceEditor
@testable import CodeEdit

@MainActor
final class EditorJumpBarSymbolTests: XCTestCase {
    private func symbol(
        _ name: String,
        startLine: Int,
        endLine: Int,
        children: [DocumentSymbol] = []
    ) -> DocumentSymbol {
        DocumentSymbol(
            name: name,
            kind: .function,
            range: LSPRange(startPair: (startLine, 0), endPair: (endLine, 0)),
            selectionRange: LSPRange(startPair: (startLine, 0), endPair: (startLine, name.count)),
            children: children
        )
    }

    func testFlattenWalksParentsBeforeChildren() {
        let inner = symbol("inner", startLine: 5, endLine: 10)
        let outer = symbol("outer", startLine: 0, endLine: 20, children: [inner])
        let flattened = EditorJumpBarSymbolModel.flatten(.optionA([outer]))
        XCTAssertEqual(flattened.map(\.name), ["outer", "inner"])
        XCTAssertEqual(flattened.map(\.depth), [0, 1])
    }

    func testEnclosingPrefersInnermostSymbol() {
        let inner = symbol("inner", startLine: 5, endLine: 10)
        let outer = symbol("outer", startLine: 0, endLine: 20, children: [inner])
        let flattened = EditorJumpBarSymbolModel.flatten(.optionA([outer]))

        let insideInner = EditorJumpBarSymbolModel.enclosing(
            in: flattened,
            cursor: CursorPosition(line: 7, column: 1)
        )
        XCTAssertEqual(insideInner?.name, "inner")

        let insideOuter = EditorJumpBarSymbolModel.enclosing(
            in: flattened,
            cursor: CursorPosition(line: 2, column: 1)
        )
        XCTAssertEqual(insideOuter?.name, "outer")

        let outside = EditorJumpBarSymbolModel.enclosing(
            in: flattened,
            cursor: CursorPosition(line: 30, column: 1)
        )
        XCTAssertNil(outside)
    }

    func testEmptyResponseIsNoSelection() {
        XCTAssertTrue(EditorJumpBarSymbolModel.flatten(nil).isEmpty)
        XCTAssertNil(
            EditorJumpBarSymbolModel.enclosing(in: [], cursor: CursorPosition(line: 1, column: 1))
        )
    }
}
