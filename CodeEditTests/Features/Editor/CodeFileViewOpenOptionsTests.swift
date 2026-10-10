//
//  CodeFileViewOpenOptionsTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/1/26.
//

import XCTest
import CodeEditSourceEditor
@testable import CodeEdit

@MainActor
final class CodeFileViewOpenOptionsTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "open-options-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// `CodeFileView.init` runs inside a SwiftUI view update, so it must not publish while it runs.
    /// Open options set before the view exists are applied on the next main-queue turn instead.
    func testOpenOptionsAreAppliedAfterInit() throws {
        let file = directory.appending(path: "main.cpp")
        try "int main() {\n    return 0;\n}\n".write(to: file, atomically: true, encoding: .utf8)
        let document = try CodeFileDocument(for: file, withContentsOf: file, ofType: "public.source-code")
        let editorInstance = EditorInstance(workspace: nil, file: CEWorkspaceFile(url: file))
        let initialPositions = editorInstance.cursorPositions
        let requested = [CursorPosition(line: 2, column: 5)]
        document.openOptions = CodeFileDocument.OpenOptions(cursorPositions: requested)

        let view = CodeFileView(editorInstance: editorInstance, codeFile: document)

        XCTAssertEqual(editorInstance.cursorPositions, initialPositions, "Published during init")
        XCTAssertNotNil(document.openOptions)

        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        XCTAssertEqual(editorInstance.cursorPositions, requested)
        XCTAssertNil(document.openOptions)
        withExtendedLifetime(view) { }
    }
}
