//
//  LSPCompletionTests.swift
//  CodeEditTests
//
//  Created by Codex on 9/14/26.
//

import XCTest
import CodeEditLanguages
@testable import CodeEditSourceEditor
import LanguageServerProtocol

@testable import CodeEdit

final class LSPCompletionTests: XCTestCase {
    @MainActor
    private final class CompletionRecorder: CodeSuggestionDelegate {
        var didRequest: ((TextViewController, CursorPosition) -> Void)?
        var response: (() async -> [CodeSuggestionEntry])?

        func completionTriggerCharacters() -> Set<String> { [".", ">", ":"] }

        func completionSuggestionsRequested(
            textView: TextViewController, cursorPosition: CursorPosition
        ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])? {
            didRequest?(textView, cursorPosition)
            if let response {
                return (cursorPosition, await response())
            }
            return nil
        }

        func completionOnCursorMove(
            textView: TextViewController, cursorPosition: CursorPosition
        ) -> [CodeSuggestionEntry]? { nil }

        func completionWindowApplyCompletion(
            item: CodeSuggestionEntry, textView: TextViewController, cursorPosition: CursorPosition?
        ) { }
    }

    @MainActor
    func testMovingCursorCancelsPendingCompletion() async throws {
        let editor = makeEditor(source: "point", language: .cpp)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentViewController = editor
        defer { window.contentViewController = nil }
        let model = SuggestionViewModel()
        let delegate = CompletionRecorder()
        let requested = expectation(description: "Pending completion request")
        var response: CheckedContinuation<[CodeSuggestionEntry], Never>?
        delegate.response = {
            await withCheckedContinuation { continuation in
                response = continuation
                requested.fulfill()
            }
        }
        var shown = false
        model.showCompletions(
            textView: editor, delegate: delegate,
            cursorPosition: CursorPosition(range: NSRange(location: 5, length: 0))
        ) { _, _ in shown = true }
        await fulfillment(of: [requested], timeout: 2)
        let pendingTask = model.itemsRequestTask
        model.cursorsUpdated(
            textView: editor, delegate: delegate,
            position: CursorPosition(range: NSRange(location: 0, length: 0)),
            close: { model.willClose() }
        )
        response?.resume(returning: [LSPCompletionEntry(item: CompletionItem(label: "point"))])
        await pendingTask?.value
        XCTAssertFalse(shown, "A response for the old cursor must not reopen the popup")
        XCTAssertTrue(model.items.isEmpty)
    }

    @MainActor
    func testAutomaticCompletionUsesUpdatedCursorAndLateServerTriggers() async throws {
        let editor = makeEditor(source: "point", language: .cpp)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentViewController = editor
        defer {
            SuggestionController.shared.close()
            window.contentViewController = nil
        }
        editor.setCursorPositions([CursorPosition(range: NSRange(location: 5, length: 0))])
        // The server becomes available after the editor's filters were configured.
        let delegate = CompletionRecorder()
        editor.completionDelegate = delegate
        let requested = expectation(description: "Completion after the inserted dot")
        delegate.didRequest = { controller, cursor in
            XCTAssertEqual(controller.text, "point.")
            XCTAssertEqual(cursor.range, NSRange(location: 6, length: 0))
            requested.fulfill()
        }
        editor.textView.insertText(".")
        await fulfillment(of: [requested], timeout: 2)
    }

    @MainActor
    private func makeEditor(
        source: String, language: CodeLanguage, coordinators: [TextViewCoordinator] = []
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
    func testCMemberCompletionImmediatelyAfterTyping() async throws {
        try await checkMemberCompletion(language: .c, declaration: "struct Point point;")
    }

    @MainActor
    func testCppMemberCompletionImmediatelyAfterTyping() async throws {
        try await checkMemberCompletion(language: .cpp, declaration: "Point point;")
    }

    @MainActor
    private func checkMemberCompletion(language: CodeLanguage, declaration: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = "struct Point { int x; int y; };\nint main() {\n    \(declaration)\n    point\n}\n"
        let file = directory.appending(path: "main.\(language.id.rawValue)")
        try source.write(to: file, atomically: true, encoding: .utf8)
        let configs = await Task.detached { LanguageServerDetector.detectServers() }.value
        let languageId = try XCTUnwrap(language.lspLanguageId)
        guard let binary = configs[languageId] else { throw XCTSkip("clangd is not installed") }
        let service = try XCTUnwrap(ServiceContainer.resolve(.singleton, LSPService.self))
        let client = try await LSPService.LanguageServerType.createServer(
            for: languageId, with: binary, workspacePath: directory.path
        )
        let key = LSPService.ClientKey(languageId, directory.path)
        service.languageClients[key] = client
        defer {
            service.languageClients[key] = nil
            Task { try? await client.shutdown() }
        }
        let document = try CodeFileDocument(for: file, withContentsOf: file, ofType: "public.source-code")
        try await client.openDocument(document)
        let editor = makeEditor(
            source: source,
            language: language,
            coordinators: [document.languageServerObjects.textCoordinator]
        )
        editor.textView.setTextStorage(try XCTUnwrap(document.content))
        let offset = (source as NSString).range(of: "point\n").location + "point".utf16.count
        editor.textView.replaceCharacters(in: NSRange(location: offset, length: 0), with: ".")
        let delegate = LSPCompletionDelegate(document: document)
        // Do not wait for the regular document-sync timer: completion must include this edit.
        let result = await delegate.completionSuggestionsRequested(
            textView: editor, cursorPosition: CursorPosition(range: NSRange(location: offset + 1, length: 0))
        )
        let labels = result?.items.map { $0.label.trimmingCharacters(in: .whitespaces) } ?? []
        XCTAssertTrue(labels.contains("x") && labels.contains("y"), "Expected Point members, got \(labels)")
        editor.textView.replaceCharacters(in: NSRange(location: offset + 1, length: 0), with: "y")
        let cursor = CursorPosition(range: NSRange(location: offset + 2, length: 0))
        let filtered = try XCTUnwrap(delegate.completionOnCursorMove(textView: editor, cursorPosition: cursor))
        XCTAssertEqual(filtered.map { $0.label.trimmingCharacters(in: .whitespaces) }, ["y"])
        delegate.completionWindowApplyCompletion(
            item: try XCTUnwrap(filtered.first), textView: editor, cursorPosition: cursor
        )
        XCTAssertTrue(editor.text.contains("point.y\n"), "Completion must replace the typed prefix: \(editor.text)")
        document.languageServerObjects.textCoordinator.destroy()
        try await client.closeDocument(file.lspURI)
    }
}

// MARK: - Completion Item Mapping & Heuristics

extension LSPCompletionTests {
    @MainActor
    func testCompletionCategoryIconsExist() {
        let categories: [LSPCompletionCategory] = [
            .function, .variable, .class, .struct, .interface, .enum, .enumMember,
            .macro, .namespace, .typeAlias, .keyword, .snippet, .file, .folder,
            .text, .color, .reference, .event, .other
        ]
        for category in categories {
            let name = LSPCompletionEntry.imageName(for: category)
            XCTAssertNotNil(
                NSImage(systemSymbolName: name, accessibilityDescription: nil),
                "Missing SF Symbol for \(category): \(name)"
            )
        }
    }

    @MainActor
    func testAllCompletionItemKindsMapped() {
        for kind in CompletionItemKind.allCases {
            let entry = LSPCompletionEntry(item: CompletionItem(label: "test", kind: kind))
            let name = entry.iconName
            XCTAssertNotNil(
                NSImage(systemSymbolName: name, accessibilityDescription: nil),
                "Missing SF Symbol for kind \(kind): \(name)"
            )
            XCTAssertFalse(name.isEmpty)
        }
    }

    @MainActor
    func testCompletionItemKindIconsAndColors() {
        let functionEntry = LSPCompletionEntry(item: CompletionItem(label: "myFunc", kind: .function))
        XCTAssertEqual(functionEntry.iconName, "function")
        XCTAssertEqual(functionEntry.imageColor, .purple)

        let variableEntry = LSPCompletionEntry(item: CompletionItem(label: "myVar", kind: .variable))
        XCTAssertEqual(variableEntry.iconName, "shippingbox")
        XCTAssertEqual(variableEntry.imageColor, .cyan)

        let classEntry = LSPCompletionEntry(item: CompletionItem(label: "MyClass", kind: .class))
        XCTAssertEqual(classEntry.iconName, "cube.fill")
        XCTAssertEqual(classEntry.imageColor, .orange)

        let structEntry = LSPCompletionEntry(item: CompletionItem(label: "MyStruct", kind: .struct))
        XCTAssertEqual(structEntry.iconName, "square.3.layers.3d.down.right")
        XCTAssertEqual(structEntry.imageColor, .orange)

        let interfaceEntry = LSPCompletionEntry(item: CompletionItem(label: "MyConcept", kind: .interface))
        XCTAssertEqual(interfaceEntry.iconName, "point.3.connected.trianglepath.dotted")
        XCTAssertEqual(interfaceEntry.imageColor, .indigo)

        let typedefEntry = LSPCompletionEntry(
            item: CompletionItem(label: "MyType", kind: .interface, detail: "typedef int MyType")
        )
        XCTAssertEqual(typedefEntry.iconName, "character.cursor.ibeam")
        XCTAssertEqual(typedefEntry.imageColor, .orange)

        let enumEntry = LSPCompletionEntry(item: CompletionItem(label: "MyEnum", kind: .enum))
        XCTAssertEqual(enumEntry.iconName, "list.bullet.rectangle")
        XCTAssertEqual(enumEntry.imageColor, .orange)

        let enumMemberEntry = LSPCompletionEntry(item: CompletionItem(label: "MY_ENUM_VAL", kind: .enumMember))
        XCTAssertEqual(enumMemberEntry.iconName, "numbersign")
        XCTAssertEqual(enumMemberEntry.imageColor, .yellow)

        let macroEntry = LSPCompletionEntry(item: CompletionItem(label: "MY_MACRO", kind: .constant))
        XCTAssertEqual(macroEntry.iconName, "number")
        XCTAssertEqual(macroEntry.imageColor, .brown)

        let moduleEntry = LSPCompletionEntry(item: CompletionItem(label: "MyNamespace", kind: .module))
        XCTAssertEqual(moduleEntry.iconName, "shippingbox.and.arrow.backward")
        XCTAssertEqual(moduleEntry.imageColor, .green)

        let keywordEntry = LSPCompletionEntry(item: CompletionItem(label: "while", kind: .keyword))
        XCTAssertEqual(keywordEntry.iconName, "key")
        XCTAssertEqual(keywordEntry.imageColor, .pink)

        let snippetEntry = LSPCompletionEntry(item: CompletionItem(label: "for", kind: .snippet))
        XCTAssertEqual(snippetEntry.iconName, "chevron.left.forwardslash.chevron.right")
        XCTAssertEqual(snippetEntry.imageColor, .secondary)

        let fileEntry = LSPCompletionEntry(item: CompletionItem(label: "stdio.h", kind: .file))
        XCTAssertEqual(fileEntry.iconName, "doc.text")
        XCTAssertEqual(fileEntry.imageColor, .secondary)
    }

    @MainActor
    func testCompletionItemCategoriesAndFallback() {
        let functionEntry = LSPCompletionEntry(item: CompletionItem(label: "myFunc", kind: .function))
        XCTAssertEqual(functionEntry.category, .function)

        let typedefEntry = LSPCompletionEntry(
            item: CompletionItem(label: "MyType", kind: .interface, detail: "typedef int MyType")
        )
        XCTAssertEqual(typedefEntry.category, .typeAlias)

        let fallbackEntry = LSPCompletionEntry(item: CompletionItem(label: "something", kind: nil))
        XCTAssertEqual(fallbackEntry.category, .other)
        XCTAssertEqual(fallbackEntry.iconName, "cube")
        XCTAssertEqual(fallbackEntry.imageColor, .secondary)
    }

    @MainActor
    func testTypeAliasAndInterfaceClassification() {
        let usingEntry = LSPCompletionEntry(
            item: CompletionItem(label: "IntAlias", kind: .interface, detail: "using IntAlias = int;")
        )
        XCTAssertEqual(usingEntry.category, .typeAlias)
        XCTAssertEqual(usingEntry.iconName, "character.cursor.ibeam")
        XCTAssertEqual(usingEntry.imageColor, .orange)

        let typedefEntry = LSPCompletionEntry(
            item: CompletionItem(label: "MyType", kind: .interface, detail: "typedef int MyType")
        )
        XCTAssertEqual(typedefEntry.category, .typeAlias)
        XCTAssertEqual(typedefEntry.iconName, "character.cursor.ibeam")
        XCTAssertEqual(typedefEntry.imageColor, .orange)

        let archetypeEntry = LSPCompletionEntry(item: CompletionItem(label: "Archetype", kind: .interface))
        XCTAssertEqual(archetypeEntry.category, .interface)
        XCTAssertEqual(archetypeEntry.iconName, "point.3.connected.trianglepath.dotted")
        XCTAssertEqual(archetypeEntry.imageColor, .indigo)

        let dataTypeEntry = LSPCompletionEntry(item: CompletionItem(label: "DataType", kind: .interface))
        XCTAssertEqual(dataTypeEntry.category, .interface)
        XCTAssertEqual(dataTypeEntry.iconName, "point.3.connected.trianglepath.dotted")
        XCTAssertEqual(dataTypeEntry.imageColor, .indigo)

        let conceptEntry = LSPCompletionEntry(
            item: CompletionItem(label: "MyConcept", kind: .interface, detail: "concept MyConcept")
        )
        XCTAssertEqual(conceptEntry.category, .interface)
        XCTAssertEqual(conceptEntry.iconName, "point.3.connected.trianglepath.dotted")
        XCTAssertEqual(conceptEntry.imageColor, .indigo)

        let typeParamEntry = LSPCompletionEntry(item: CompletionItem(label: "T", kind: .typeParameter))
        XCTAssertEqual(typeParamEntry.category, .typeAlias)
        XCTAssertEqual(typeParamEntry.iconName, "character.cursor.ibeam")
        XCTAssertEqual(typeParamEntry.imageColor, .orange)
    }

    @MainActor
    func testCompletionItemDeprecation() {
        let deprecatedEntry = LSPCompletionEntry(
            item: CompletionItem(label: "legacyFunc", kind: .function, deprecated: true)
        )
        XCTAssertTrue(deprecatedEntry.deprecated)

        let activeEntry = LSPCompletionEntry(
            item: CompletionItem(label: "activeFunc", kind: .function, deprecated: false)
        )
        XCTAssertFalse(activeEntry.deprecated)

        let defaultEntry = LSPCompletionEntry(
            item: CompletionItem(label: "defaultFunc", kind: .function)
        )
        XCTAssertFalse(defaultEntry.deprecated)
    }
}
