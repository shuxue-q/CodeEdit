//
//  LSPPositionTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 9/27/26.
//

import XCTest
import CodeEditTextView
import LanguageClient
import LanguageServerProtocol
import TextStory

@testable import CodeEdit

final class LSPPositionTests: XCTestCase {
    private struct OffsetCase {
        let text: String
        let offset: Int
        let position: Position
    }

    func testOffsets() {
        let cases = [
            OffsetCase(text: "", offset: 0, position: Position(line: 0, character: 0)),
            OffsetCase(text: "abc", offset: 0, position: Position(line: 0, character: 0)),
            OffsetCase(text: "abc", offset: 3, position: Position(line: 0, character: 3)),
            OffsetCase(text: "ab\n", offset: 2, position: Position(line: 0, character: 2)),
            OffsetCase(text: "ab\n", offset: 3, position: Position(line: 1, character: 0)),
            OffsetCase(text: "ab\ncd", offset: 3, position: Position(line: 1, character: 0)),
            OffsetCase(text: "ab\ncd", offset: 4, position: Position(line: 1, character: 1)),
            OffsetCase(text: "a\r\nb", offset: 1, position: Position(line: 0, character: 1)),
            OffsetCase(text: "a\r\nb", offset: 2, position: Position(line: 0, character: 1)),
            OffsetCase(text: "a\r\nb", offset: 3, position: Position(line: 1, character: 0)),
            OffsetCase(text: "a\r\nb", offset: 4, position: Position(line: 1, character: 1))
        ]

        for item in cases {
            let position = TextView.lspPosition(at: item.offset, in: item.text as NSString)
            XCTAssertEqual(position, item.position, "\(item.text.debugDescription) at \(item.offset)")
        }
    }

    @MainActor
    func testPositionUsesTextUpdatedInsideBeginEditing() {
        let textView = TextView(string: "void foo() {}\n")
        textView.textStorage.beginEditing()
        textView.textStorage.replaceCharacters(in: NSRange(location: 12, length: 0), with: "\n")
        let position = textView.lspPositionFrom(offset: 13)
        textView.textStorage.endEditing()

        XCTAssertEqual(position, Position(line: 1, character: 0))
    }
}

extension LanguageServerCodeFileDocumentTests {
    /// Newline and indent filters write straight into the text storage, inside one editing group.
    /// The second edit has to be measured against the text after the newline, not the stale line index.
    @MainActor
    func testFilterMutationsReportPositionsInTheUpdatedText() async throws {
        let (connection, server) = try await makeTestServer()
        let (_, fileManager) = try makeTestWorkspace()
        _ = try fileManager.addFile(fileName: "example", toFile: fileManager.workspaceItem, useExtension: "swift")
        guard let file = fileManager.childrenOfFile(fileManager.workspaceItem)?.first else {
            XCTFail("No File")
            return
        }

        let codeFile = try await openCodeFile(
            for: server,
            connection: connection,
            file: file,
            syncOption: .optionA(.init(change: .incremental))
        )
        let source = "void foo() {}\n"
        codeFile.content?.replaceCharacters(
            in: NSRange(location: 0, length: codeFile.content?.length ?? 0),
            with: source
        )

        let textView = TextView(string: "")
        textView.setTextStorage(codeFile.content!)
        textView.delegate = codeFile.languageServerObjects.textCoordinator
        codeFile.languageServerObjects.textCoordinator.setUpUpdatesTask()

        let insertAt = (source as NSString).range(of: "}").location
        textView.textStorage.beginEditing()
        textView.applyMutation(TextMutation(insert: "\n", at: insertAt, limit: textView.length))
        textView.applyMutation(TextMutation(insert: "    ", at: insertAt + 1, limit: textView.length))
        textView.textStorage.endEditing()

        await waitForClientState(
            (
                [.initialize],
                [.initialized, .textDocumentDidOpen, .textDocumentDidChange]
            ),
            connection: connection,
            description: "Filter edits produce one didChange"
        )

        var changes: [TextDocumentContentChangeEvent] = []
        for notification in connection.clientNotifications {
            guard case let .textDocumentDidChange(params) = notification else { continue }
            changes.append(contentsOf: params.contentChanges)
        }

        XCTAssertEqual(changes.map(\.text), ["\n", "    "])
        XCTAssertEqual(changes[0].range, LSPRange(startPair: (0, insertAt), endPair: (0, insertAt)))
        XCTAssertEqual(changes[1].range, LSPRange(startPair: (1, 0), endPair: (1, 0)))
        XCTAssertEqual(textView.string, "void foo() {\n    }\n")
    }
}
