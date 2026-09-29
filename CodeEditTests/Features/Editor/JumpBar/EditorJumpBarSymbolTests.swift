//
//  EditorJumpBarSymbolTests.swift
//  CodeEditTests
//
//  Created by CodeEdit on 9/17/26.
//

import XCTest
import LanguageServerProtocol
import CodeEditLanguages
import CodeEditSourceEditor
@testable import CodeEdit

@MainActor
final class EditorJumpBarSymbolTests: XCTestCase {
    private func symbol(
        _ name: String,
        kind: SymbolKind = .function,
        startLine: Int,
        endLine: Int,
        children: [DocumentSymbol] = [],
        detail: String? = nil
    ) -> DocumentSymbol {
        DocumentSymbol(
            name: name,
            detail: detail,
            kind: kind,
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
        XCTAssertNil(flattened[0].parentID)
        XCTAssertEqual(flattened[1].parentID, flattened[0].id)
    }

    func testSiblingsShareAParent() {
        let left = symbol("left", startLine: 1, endLine: 2)
        let right = symbol("right", startLine: 3, endLine: 4)
        let outer = symbol("outer", startLine: 0, endLine: 10, children: [left, right])
        let flattened = EditorJumpBarSymbolModel.flatten(.optionA([outer]))
        let names = EditorJumpBarSymbolModel.siblings(of: flattened[1], in: flattened).map(\.name)
        XCTAssertEqual(names, ["left", "right"])
    }

    func testPathPlacesFunctionImmediatelyAboveVariable() {
        let count = symbol("count", kind: .variable, startLine: 6, endLine: 6)
        let run = symbol("run", startLine: 4, endLine: 8, children: [count])
        let stop = symbol("stop", startLine: 9, endLine: 12)
        let box = symbol("Box", kind: .class, startLine: 0, endLine: 14, children: [run, stop])
        let flattened = EditorJumpBarSymbolModel.flatten(.optionA([box]))
        let segments = EditorJumpBarPath.segments(
            documentSymbols: flattened,
            syntaxSymbols: [],
            cursorVariable: nil,
            cursor: CursorPosition(line: 7, column: 1)
        )

        XCTAssertEqual(segments.map(\.title), ["Box", "run", "count"])
        XCTAssertEqual(segments.map(\.role), [.scope, .function, .variable])
        XCTAssertEqual(segments[1].items.map(\.title), ["run", "stop"])
        XCTAssertEqual(segments[2].items.map(\.title), ["count"])
    }

    func testPathAppendsLocalVariableUnderFunction() {
        let format = symbol("formatCode", startLine: 0, endLine: 20, detail: "(text:)")
        let flattened = EditorJumpBarSymbolModel.flatten(.optionA([format]))
        let local = EditorJumpBarSyntaxSymbol(
            id: "local",
            name: "local",
            kind: .variable,
            nameLine: 5,
            nameColumn: 3,
            startLine: 5,
            startColumn: 3,
            endLine: 5,
            endColumn: 8,
            parentID: "fn"
        )
        let param = EditorJumpBarSyntaxSymbol(
            id: "param",
            name: "param",
            kind: .variable,
            nameLine: 1,
            nameColumn: 20,
            startLine: 1,
            startColumn: 20,
            endLine: 1,
            endColumn: 25,
            parentID: "fn"
        )
        let segments = EditorJumpBarPath.segments(
            documentSymbols: flattened,
            syntaxSymbols: [param, local],
            cursorVariable: local,
            cursor: CursorPosition(line: 5, column: 3)
        )

        XCTAssertEqual(segments.map(\.title), ["formatCode(text:)", "local"])
        XCTAssertEqual(segments[1].items.map(\.title), ["param", "local"])
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
