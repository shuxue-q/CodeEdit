//
//  LSPIncludeAndPairTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/16/26.
//

import XCTest
import CodeEditSourceEditor
import CodeEditLanguages
import LanguageServerProtocol
@testable import CodeEdit

final class LSPIncludeAndPairTests: XCTestCase {
    @MainActor
    private func makeEditor(
        source: String,
        language: CodeLanguage,
        coordinators: [TextViewCoordinator] = []
    ) -> TextViewController {
        let editor = TextViewController(
            string: source,
            language: language,
            configuration: .init(appearance: .init(
                theme: ThemeModel.shared.themes[0].editor.editorTheme,
                font: .monospacedSystemFont(ofSize: 13, weight: .regular),
                wrapLines: false
            )),
            cursorPositions: [],
            highlightProviders: [],
            coordinators: coordinators
        )
        editor.loadView()
        return editor
    }

    @MainActor
    func testIncludeCompletionWhenTypingHash() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = "#\n"
        let file = directory.appending(path: "main.c")
        try source.write(to: file, atomically: true, encoding: .utf8)
        let configs = await Task.detached { LanguageServerDetector.detectServers() }.value
        guard let binary = configs["c"] else { throw XCTSkip("clangd is not installed") }
        let service = try XCTUnwrap(ServiceContainer.resolve(.singleton, LSPService.self))
        let client = try await LSPService.LanguageServerType.createServer(
            for: "c", with: binary, workspacePath: directory.path
        )
        let key = LSPService.ClientKey("c", directory.path)
        service.languageClients[key] = client
        defer {
            service.languageClients[key] = nil
            Task { try? await client.shutdown() }
        }
        let document = try CodeFileDocument(for: file, withContentsOf: file, ofType: "public.source-code")
        try await client.openDocument(document)
        let editor = makeEditor(
            source: source,
            language: .c,
            coordinators: [document.languageServerObjects.textCoordinator]
        )
        editor.textView.setTextStorage(try XCTUnwrap(document.content))
        let delegate = LSPCompletionDelegate(document: document)
        let cursor = CursorPosition(range: NSRange(location: 1, length: 0))
        let result = await delegate.completionSuggestionsRequested(
            textView: editor, cursorPosition: cursor
        )
        let items = try XCTUnwrap(result?.items)
        XCTAssertGreaterThanOrEqual(items.count, 2, "Expected at least 2 completions for #")
        XCTAssertEqual(items[0].label, "#include <insert>", "Item 0 must be system header include")
        XCTAssertEqual(items[1].label, "#include \"insert\"", "Item 1 must be user header include")
        try verifyAngleInclude(
            item: items[0], editor: editor, delegate: delegate, cursor: cursor
        )
        try verifyQuoteInclude(
            item: items[1], editor: editor, delegate: delegate, cursor: cursor
        )
    }

    @MainActor
    private func verifyAngleInclude(
        item: CodeSuggestionEntry,
        editor: TextViewController,
        delegate: LSPCompletionDelegate,
        cursor: CursorPosition
    ) throws {
        delegate.completionWindowApplyCompletion(item: item, textView: editor, cursorPosition: cursor)
        XCTAssertTrue(editor.text.hasPrefix("#include <>"))
        let selection = try XCTUnwrap(editor.textView.selectionManager.textSelections.first)
        let expectedCursor = (editor.text as NSString).range(of: "<>").location + 1
        XCTAssertEqual(selection.range.location, expectedCursor, "Cursor should be inside <>")

        editor.textView.replaceCharacters(in: selection.range, with: ">")
        let afterAngle = (editor.text as NSString).range(of: "<>").location + 2
        let overtypeSel = try XCTUnwrap(editor.textView.selectionManager.textSelections.first)
        XCTAssertEqual(overtypeSel.range.location, afterAngle, "Typing > should jump out of <>")

        editor.textView.selectionManager.setSelectedRange(NSRange(location: expectedCursor, length: 0))
        editor.textView.replaceCharacters(in: NSRange(location: expectedCursor, length: 0), with: "\t")
        let tabbedSelection = try XCTUnwrap(editor.textView.selectionManager.textSelections.first)
        XCTAssertEqual(tabbedSelection.range.location, afterAngle, "Tab should jump out of <>")
    }

    @MainActor
    private func verifyQuoteInclude(
        item: CodeSuggestionEntry,
        editor: TextViewController,
        delegate: LSPCompletionDelegate,
        cursor: CursorPosition
    ) throws {
        let entireRange = NSRange(location: 0, length: (editor.text as NSString).length)
        editor.textView.replaceCharacters(in: entireRange, with: "#\n")
        delegate.completionWindowApplyCompletion(item: item, textView: editor, cursorPosition: cursor)
        XCTAssertTrue(editor.text.hasPrefix("#include \"\""))
        let selection = try XCTUnwrap(editor.textView.selectionManager.textSelections.first)
        let expectedCursor = (editor.text as NSString).range(of: "\"\"").location + 1
        XCTAssertEqual(selection.range.location, expectedCursor, "Cursor should be inside \"\"")

        editor.textView.replaceCharacters(in: selection.range, with: "\"")
        let afterQuote = (editor.text as NSString).range(of: "\"\"").location + 2
        let overtypeSel = try XCTUnwrap(editor.textView.selectionManager.textSelections.first)
        XCTAssertEqual(overtypeSel.range.location, afterQuote, "Typing \" should jump out of \"\"")

        editor.textView.selectionManager.setSelectedRange(NSRange(location: expectedCursor, length: 0))
        editor.textView.replaceCharacters(in: NSRange(location: expectedCursor, length: 0), with: "\t")
        let tabbedSel = try XCTUnwrap(editor.textView.selectionManager.textSelections.first)
        XCTAssertEqual(tabbedSel.range.location, afterQuote, "Tab should jump out of \"\"")
    }

    @MainActor
    func testQuoteAutoCloseAndTabJump() {
        let editor = makeEditor(source: "", language: .c)
        // Type opening quote
        editor.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "\"")
        XCTAssertEqual(editor.text, "\"\"")
        let initialSelection = editor.textView.selectionManager.textSelections.first
        XCTAssertEqual(initialSelection?.range.location, 1, "Cursor should be inside quotes")

        // Type quote again to jump out
        editor.textView.replaceCharacters(in: NSRange(location: 1, length: 0), with: "\"")
        XCTAssertEqual(editor.text, "\"\"", "Typing quote again should not insert extra quote")
        let jumpedSelection = editor.textView.selectionManager.textSelections.first
        XCTAssertEqual(jumpedSelection?.range.location, 2, "Cursor should have jumped past quote")

        // In a new editor, test Tab key jumping out
        let tabEditor = makeEditor(source: "", language: .c)
        tabEditor.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "\"")
        XCTAssertEqual(tabEditor.text, "\"\"")
        tabEditor.textView.replaceCharacters(in: NSRange(location: 1, length: 0), with: "\t")
        XCTAssertEqual(tabEditor.text, "\"\"", "Tab key should not insert tab character when jumping out")
        let tabJumpedSelection = tabEditor.textView.selectionManager.textSelections.first
        XCTAssertEqual(tabJumpedSelection?.range.location, 2, "Tab should have jumped past quote")

        // Test typing text inside quotes and jumping out with Tab
        let contentEditor = makeEditor(source: "", language: .c)
        contentEditor.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "\"")
        contentEditor.textView.replaceCharacters(in: NSRange(location: 1, length: 0), with: "hello")
        XCTAssertEqual(contentEditor.text, "\"hello\"")
        contentEditor.textView.replaceCharacters(in: NSRange(location: 6, length: 0), with: "\t")
        XCTAssertEqual(contentEditor.text, "\"hello\"")
        let contentTabJump = contentEditor.textView.selectionManager.textSelections.first
        XCTAssertEqual(contentTabJump?.range.location, 7, "Tab should jump past quote after typing content")

        // Test typing > to jump out of angle brackets
        let angleEditor = makeEditor(source: "#include <>", language: .c)
        angleEditor.textView.replaceCharacters(in: NSRange(location: 10, length: 0), with: ">")
        XCTAssertEqual(angleEditor.text, "#include <>", "Typing > should not insert extra >")
        let angleJump = angleEditor.textView.selectionManager.textSelections.first
        XCTAssertEqual(angleJump?.range.location, 11, "Cursor should jump past >")

        // Test typing < after #include auto-pairs to <>
        let manualAngleEditor = makeEditor(source: "#include ", language: .c)
        manualAngleEditor.textView.replaceCharacters(in: NSRange(location: 9, length: 0), with: "<")
        XCTAssertEqual(manualAngleEditor.text, "#include <>", "Typing < after #include should auto-pair <>")
        let manualAngleSel = manualAngleEditor.textView.selectionManager.textSelections.first
        XCTAssertEqual(manualAngleSel?.range.location, 10, "Cursor should be inside <>")

        // Tab jump out of manually paired <>
        manualAngleEditor.textView.replaceCharacters(in: NSRange(location: 10, length: 0), with: "\t")
        let manualAngleTabSel = manualAngleEditor.textView.selectionManager.textSelections.first
        XCTAssertEqual(manualAngleTabSel?.range.location, 11, "Tab should jump past >")

        // Overtype > out of manually paired <>
        let manualAngleOvertypeEditor = makeEditor(source: "#include ", language: .c)
        manualAngleOvertypeEditor.textView.replaceCharacters(in: NSRange(location: 9, length: 0), with: "<")
        manualAngleOvertypeEditor.textView.replaceCharacters(in: NSRange(location: 10, length: 0), with: ">")
        let manualAngleOvertypeSel = manualAngleOvertypeEditor.textView.selectionManager.textSelections.first
        XCTAssertEqual(manualAngleOvertypeSel?.range.location, 11, "Typing > should jump past >")
    }

    @MainActor
    func testAutoPairBackspaceDelete() {
        let editor = makeEditor(source: "", language: .c)
        editor.textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "\"")
        XCTAssertEqual(editor.text, "\"\"")
        // Press backspace inside ""
        editor.textView.replaceCharacters(in: NSRange(location: 0, length: 1), with: "")
        XCTAssertEqual(editor.text, "", "Backspace inside empty quotes should delete both quotes")
    }
}
