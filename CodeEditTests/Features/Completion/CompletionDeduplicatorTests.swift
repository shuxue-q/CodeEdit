//
//  CompletionDeduplicatorTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import LanguageServerProtocol
import XCTest
@testable import CodeEdit

final class CompletionDeduplicatorTests: XCTestCase {
    private func candidate(
        label: String,
        kind: LSPCompletionCategory,
        source: CompletionSource
    ) -> CompletionCandidate {
        CompletionCandidate(
            id: UUID().uuidString,
            label: label,
            filterText: label,
            kind: kind,
            source: source,
            payload: .plain(insertText: label)
        )
    }

    func testSnippetDropsKeywordAndPlainDuplicatesInTheSameGroup() {
        let candidates = [
            candidate(label: "for", kind: .snippet, source: .snippet),
            candidate(label: "for", kind: .keyword, source: .keyword),
            candidate(label: "for", kind: .keyword, source: .ai)
        ]
        let result = CompletionDeduplicator.deduplicate(candidates)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.source, .snippet)
    }

    func testSnippetDropsLanguageServerKeywordWithTheSameLabel() {
        let serverKeyword = CompletionCandidate(
            id: "lsp.for",
            label: "for",
            filterText: "for",
            kind: .keyword,
            source: .lsp,
            payload: .lsp(CompletionItem(label: "for", kind: .keyword))
        )
        let result = CompletionDeduplicator.deduplicate([
            serverKeyword,
            candidate(label: "for", kind: .snippet, source: .snippet)
        ])
        XCTAssertEqual(result.map(\.source), [.snippet])
    }

    func testExactDuplicatesKeepTheHighestPrioritySource() {
        let candidates = [
            candidate(label: "printf", kind: .function, source: .ai),
            candidate(label: "printf", kind: .function, source: .lsp)
        ]
        let result = CompletionDeduplicator.deduplicate(candidates)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.source, .lsp)
        XCTAssertEqual(result.first?.mergedSources, [.lsp, .ai])
    }

    func testDifferentKindsWithTheSameLabelAreKeptSeparately() {
        let candidates = [
            candidate(label: "Point", kind: .class, source: .lsp),
            candidate(label: "Point", kind: .function, source: .lsp)
        ]
        let result = CompletionDeduplicator.deduplicate(candidates)
        XCTAssertEqual(result.count, 2)
    }

    func testNormalizedLabelStripsClangdIncludeMarker() {
        XCTAssertEqual(CompletionDeduplicator.normalizedLabel("•printf"), "printf")
        XCTAssertEqual(CompletionDeduplicator.normalizedLabel(" printf "), "printf")
    }

    func testPreservesFirstSeenGroupOrder() {
        let candidates = [
            candidate(label: "b", kind: .variable, source: .lsp),
            candidate(label: "a", kind: .variable, source: .lsp),
            candidate(label: "b", kind: .variable, source: .keyword)
        ]
        let result = CompletionDeduplicator.deduplicate(candidates)
        XCTAssertEqual(result.map(\.label), ["b", "a"])
    }
}
