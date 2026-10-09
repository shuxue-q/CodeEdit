//
//  LSPCompletionApplyTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
import CodeEditLanguages
import CodeEditSourceEditor
import LanguageServerProtocol
@testable import CodeEdit

/// Accepting an LSP completion with `additionalTextEdits`, without a running language server.
final class LSPCompletionApplyTests: XCTestCase {
    private static let source = "int main() {\n    std::vec\n}\n"

    @MainActor
    private func makeEditor(source: String) -> TextViewController {
        let editor = TextViewController(
            string: source,
            language: .cpp,
            configuration: .init(appearance: .init(
                theme: ThemeModel.shared.themes[0].editor.editorTheme,
                font: .monospacedSystemFont(ofSize: 13, weight: .regular),
                wrapLines: false
            )),
            cursorPositions: [],
            highlightProviders: [],
            coordinators: []
        )
        editor.loadView()
        return editor
    }

    /// `std::vec` completed to `std::vector`, with clangd's `#include <vector>` as an additional edit.
    @MainActor
    private func vectorCandidate(editor: TextViewController, cursor: Int) throws -> CompletionCandidate {
        let item = CompletionItem(
            label: " vector",
            kind: .class,
            textEdit: .optionA(TextEdit(
                range: LSPRange(
                    start: Position(line: 1, character: 9),
                    end: Position(line: 1, character: 12)
                ),
                newText: "vector"
            )),
            additionalTextEdits: [
                TextEdit(
                    range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 0)),
                    newText: "#include <vector>\n"
                )
            ]
        )
        return CompletionCandidate(
            id: "lsp.test",
            label: item.label,
            filterText: "vector",
            kind: .class,
            source: .lsp,
            payload: .lsp(item)
        )
    }

    @MainActor
    func testIncludeInsertedAboveLeavesCaretOnTheCompletedSymbol() throws {
        let editor = makeEditor(source: Self.source)
        let cursor = (Self.source as NSString).range(of: "vec").max
        editor.textView.selectionManager.setSelectedRange(NSRange(location: cursor, length: 0))
        let provider = LSPCompletionProvider(document: CodeFileDocument())

        provider.apply(
            try vectorCandidate(editor: editor, cursor: cursor),
            textView: editor,
            cursorPosition: CursorPosition(range: NSRange(location: cursor, length: 0))
        )

        let expected = "#include <vector>\nint main() {\n    std::vector\n}\n"
        XCTAssertEqual(editor.text, expected)
        let caret = editor.textView.selectionManager.textSelections.first?.range.location
        XCTAssertEqual(caret, (expected as NSString).range(of: "std::vector").max)
    }

    @MainActor
    func testAcceptanceIsOneUndoStep() throws {
        let editor = makeEditor(source: Self.source)
        let cursor = (Self.source as NSString).range(of: "vec").max
        editor.textView.selectionManager.setSelectedRange(NSRange(location: cursor, length: 0))
        let provider = LSPCompletionProvider(document: CodeFileDocument())

        provider.apply(
            try vectorCandidate(editor: editor, cursor: cursor),
            textView: editor,
            cursorPosition: CursorPosition(range: NSRange(location: cursor, length: 0))
        )
        editor.textView.undoManager?.undo()

        XCTAssertEqual(editor.text, Self.source)
    }

    @MainActor
    func testDisablingTheSettingSkipsAdditionalEdits() throws {
        let original = Settings.shared.preferences.textEditing.completion.applyAdditionalEdits
        Settings.shared.preferences.textEditing.completion.applyAdditionalEdits = false
        defer { Settings.shared.preferences.textEditing.completion.applyAdditionalEdits = original }
        let editor = makeEditor(source: Self.source)
        let cursor = (Self.source as NSString).range(of: "vec").max
        editor.textView.selectionManager.setSelectedRange(NSRange(location: cursor, length: 0))
        let provider = LSPCompletionProvider(document: CodeFileDocument())

        provider.apply(
            try vectorCandidate(editor: editor, cursor: cursor),
            textView: editor,
            cursorPosition: CursorPosition(range: NSRange(location: cursor, length: 0))
        )

        XCTAssertEqual(editor.text, "int main() {\n    std::vector\n}\n")
    }

    func testSettingDecodesWhenKeyIsMissing() throws {
        let decoded = try JSONDecoder().decode(
            SettingsData.TextEditingSettings.CompletionBehaviorSettings.self,
            from: Data("{}".utf8)
        )
        XCTAssertTrue(decoded.applyAdditionalEdits)
    }
}
