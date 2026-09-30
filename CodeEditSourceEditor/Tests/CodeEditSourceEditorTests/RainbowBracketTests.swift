import XCTest
import AppKit
import CodeEditTextView
import CodeEditLanguages
@testable import CodeEditSourceEditor

// swiftlint:disable all

final class RainbowBracketTests: XCTestCase {
    /// Runs a highlight query over the whole document and returns only bracket highlights as `(character, level)`.
    @MainActor
    private func brackets(in source: String, language: CodeLanguage = .swift) -> [(Character, Int)] {
        let textView = Mock.textView()
        textView.setText(source)
        let client = Mock.treeSitterClient(forceSync: true)
        client.setUp(textView: textView, codeLanguage: language)
        var found: [HighlightRange] = []
        client.queryHighlightsFor(textView: textView, range: NSRange(location: 0, length: (source as NSString).length)) {
            if case .success(let highlights) = $0 { found = highlights }
        }
        let text = source as NSString
        return found.compactMap { highlight in
            guard let level = highlight.capture?.bracketLevelIndex else { return nil }
            return (Character(text.substring(with: highlight.range)), level)
        }
    }

    @MainActor
    func test_nestedBracketsGetIncreasingLevels() {
        let result = brackets(in: "let x = f(a[0], { (b) in b })")
        XCTAssertEqual(result.map { String($0.0) }.joined(), "([]{()})")
        XCTAssertEqual(result.map(\.1), [0, 1, 1, 1, 2, 2, 1, 0])
    }

    @MainActor
    func test_bracketsInStringsAndCommentsAreIgnored() {
        let result = brackets(in: "let s = \"(((\" // )))\nlet t = (1)")
        XCTAssertEqual(result.map { String($0.0) }.joined(), "()")
        XCTAssertEqual(result.map(\.1), [0, 0])
    }

    @MainActor
    func test_queryStartingMidDocumentUsesEnclosingDepth() {
        let source = "foo(bar(baz(1), 2), 3)"
        let textView = Mock.textView()
        textView.setText(source)
        let client = Mock.treeSitterClient(forceSync: true)
        client.setUp(textView: textView, codeLanguage: .swift)
        let start = (source as NSString).range(of: "baz").location
        var levels: [Int] = []
        client.queryHighlightsFor(textView: textView, range: NSRange(location: start, length: source.count - start)) {
            if case .success(let highlights) = $0 { levels = highlights.compactMap { $0.capture?.bracketLevelIndex } }
        }
        // "(1)" is at depth 2, then ")" closing bar( at 1, ")" closing foo( at 0.
        XCTAssertEqual(levels, [2, 2, 1, 0])
    }

    func test_levelsWrapAroundCycle() {
        XCTAssertEqual(CaptureName.bracketLevel(0), .bracketLevel0)
        XCTAssertEqual(CaptureName.bracketLevel(CaptureName.bracketLevelCount + 2), .bracketLevel2)
    }

    func test_overlayCarvesBracketsOutOfBroaderHighlights() {
        let highlights = [HighlightRange(range: NSRange(location: 0, length: 6), capture: .string)]
        let brackets = [HighlightRange(range: NSRange(location: 2, length: 1), capture: .bracketLevel1)]
        let merged = TreeSitterClient.overlay(brackets: brackets, on: highlights)
        XCTAssertEqual(merged.map(\.range), [NSRange(location: 0, length: 2), NSRange(location: 2, length: 1), NSRange(location: 3, length: 3)])
        XCTAssertEqual(merged.map(\.capture), [.string, .bracketLevel1, .string])
    }

    func test_overlayKeepsBracketsBetweenHighlights() {
        let highlights = [
            HighlightRange(range: NSRange(location: 0, length: 2), capture: .keyword),
            HighlightRange(range: NSRange(location: 6, length: 2), capture: .keyword)
        ]
        let brackets = [
            HighlightRange(range: NSRange(location: 3, length: 1), capture: .bracketLevel0),
            HighlightRange(range: NSRange(location: 9, length: 1), capture: .bracketLevel0)
        ]
        let merged = TreeSitterClient.overlay(brackets: brackets, on: highlights)
        XCTAssertEqual(merged.map(\.range.location), [0, 3, 6, 9])
    }

    func test_themeUsesExplicitColorsAndFallsBackByBrightness() {
        var theme = Mock.theme()
        theme.bracketColors = [.red, .green, .blue]
        XCTAssertEqual(theme.colorFor(.bracketLevel0), .red)
        XCTAssertEqual(theme.colorFor(.bracketLevel4), .green)

        theme.bracketColors = nil
        theme.background = NSColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        XCTAssertEqual(theme.resolvedBracketColors, EditorTheme.darkBracketColors)
        theme.background = NSColor(srgbRed: 0.98, green: 0.98, blue: 0.98, alpha: 1)
        XCTAssertEqual(theme.resolvedBracketColors, EditorTheme.lightBracketColors)
    }
}
