//
//  DocumentWordProviderTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
import CodeEditLanguages
import CodeEditSourceEditor
@testable import CodeEdit

final class DocumentWordProviderTests: XCTestCase {
    // MARK: - Tokenizer

    func testTokenizerKeepsIdentifiersOfThreeOrMoreCharactersWithCounts() {
        let words = DocumentWordTokenizer.words(in: "int counter = a + counter; // ab 12abc _tmp")
        XCTAssertEqual(words["counter"], 2)
        XCTAssertEqual(words["int"], 1)
        XCTAssertEqual(words["_tmp"], 1)
        XCTAssertNil(words["a"], "Too short")
        XCTAssertNil(words["ab"], "Too short")
        XCTAssertNil(words["12abc"], "Starts with a digit")
    }

    func testTokenizerKeepsNonASCIIIdentifiers() {
        XCTAssertEqual(DocumentWordTokenizer.words(in: "let größe = 1")["größe"], 1)
    }

    func testTokenizerCapsDistinctWordsKeepingTheMostFrequent() {
        var text = (0..<(DocumentWordTokenizer.maximumWords + 500)).map { "word\($0)" }.joined(separator: " ")
        text += String(repeating: " frequent", count: 5)
        let words = DocumentWordTokenizer.words(in: text)
        XCTAssertEqual(words.count, DocumentWordTokenizer.maximumWords)
        XCTAssertEqual(words["frequent"], 5)
    }

    // MARK: - Provider

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
            highlightProviders: []
        )
        editor.loadView()
        return editor
    }

    private func context(
        _ text: String,
        prefix: String,
        intent: CompletionIntent = .expression,
        isExplicit: Bool = false
    ) -> CompletionContext {
        CompletionContext(
            prefix: prefix,
            prefixRange: NSRange(location: (text as NSString).length - prefix.count, length: prefix.count),
            intent: intent,
            languageId: "cpp",
            documentText: text,
            cursorOffset: (text as NSString).length,
            isExplicit: isExplicit
        )
    }

    @MainActor
    func testOffersDocumentIdentifiersMatchingThePrefixButNotTheWordBeingTyped() async {
        let text = "int counter = 0;\ncount_items(counter);\ncou"
        let provider = DocumentWordProvider()
        let result = await provider.candidates(
            for: context(text, prefix: "cou"),
            textView: makeEditor(source: text)
        )
        XCTAssertEqual(result.map(\.label).sorted(), ["count_items", "counter"])
        XCTAssertTrue(result.allSatisfy { $0.source == .word && $0.kind == .text })
    }

    @MainActor
    func testKeepsTheWordAtTheCursorWhenTheDocumentUsesItElsewhere() async {
        let text = "int counter = 0;\ncounter"
        let result = await DocumentWordProvider().candidates(
            for: context(text, prefix: "counter"),
            textView: makeEditor(source: text)
        )
        XCTAssertEqual(result.map(\.label), ["counter"])
    }

    @MainActor
    func testOneCharacterPrefixOffersNothingUnlessExplicit() async {
        let text = "int counter = 0;\nc"
        let provider = DocumentWordProvider()
        let editor = makeEditor(source: text)
        let typed = await provider.candidates(for: context(text, prefix: "c"), textView: editor)
        XCTAssertTrue(typed.isEmpty)
        let explicit = await provider.candidates(for: context(text, prefix: "c", isExplicit: true), textView: editor)
        XCTAssertEqual(explicit.map(\.label), ["counter"])
    }

    @MainActor
    func testOnlyOffersWordsWhereANamedValueOrTypeMakesSense() async {
        let text = "int counter = 0;\ncou"
        let provider = DocumentWordProvider()
        let editor = makeEditor(source: text)
        for intent in CompletionIntent.allCases {
            let result = await provider.candidates(for: context(text, prefix: "cou", intent: intent), textView: editor)
            XCTAssertEqual(
                !result.isEmpty,
                CompletionIntentPolicy.documentWordIntents.contains(intent),
                "\(intent)"
            )
        }
    }

    @MainActor
    func testTokenizationIsCachedPerContent() async {
        let text = "int counter = 0;\ncou"
        let provider = DocumentWordProvider()
        let editor = makeEditor(source: text)
        _ = await provider.candidates(for: context(text, prefix: "cou"), textView: editor)
        _ = await provider.candidates(for: context(text, prefix: "cou"), textView: editor)
        XCTAssertEqual(provider.tokenizationCount, 1)
        let changed = text + "n"
        _ = await provider.candidates(for: context(changed, prefix: "coun"), textView: editor)
        XCTAssertEqual(provider.tokenizationCount, 2)
    }

    @MainActor
    func testApplyReplacesTheTypedPrefix() throws {
        let text = "int counter = 0;\ncou"
        let editor = makeEditor(source: text)
        let candidate = CompletionCandidate(
            id: "word.counter", label: "counter", filterText: "counter", kind: .text, source: .word,
            payload: .plain(insertText: "counter")
        )
        let cursor = (text as NSString).length
        DocumentWordProvider().apply(
            candidate,
            textView: editor,
            cursorPosition: CursorPosition(range: NSRange(location: cursor, length: 0))
        )
        XCTAssertEqual(editor.text, "int counter = 0;\ncounter")
    }

    // MARK: - Policy and pipeline

    func testWordsAreWeightedLowInTheAllowedIntentsAndExcludedElsewhere() {
        XCTAssertEqual(
            CompletionIntentPolicy.weight(kind: .text, source: .word, intent: .expression, isExplicit: false),
            0.25
        )
        XCTAssertNil(CompletionIntentPolicy.weight(kind: .text, source: .word, intent: .memberAccess, isExplicit: true))
        XCTAssertNil(CompletionIntentPolicy.weight(kind: .text, source: .word, intent: .comment, isExplicit: true))
    }

    func testAWordIsDroppedWhenAnotherSourceHasTheSameLabel() {
        let word = CompletionCandidate(
            id: "w", label: "counter", filterText: "counter", kind: .text, source: .word,
            payload: .plain(insertText: "counter")
        )
        let symbol = CompletionCandidate(
            id: "l", label: "counter", filterText: "counter", kind: .variable, source: .lsp,
            payload: .plain(insertText: "counter")
        )
        let result = CompletionDeduplicator.deduplicate([word, symbol])
        XCTAssertEqual(result.map(\.id), ["l"])
        XCTAssertEqual(CompletionDeduplicator.deduplicate([word]).map(\.id), ["w"])
    }

    @MainActor
    func testWordBadge() {
        XCTAssertEqual(CompletionPresenter.badge(for: .word)?.accessibilityLabel, "Word")
    }
}
