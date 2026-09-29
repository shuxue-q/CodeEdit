//
//  CompletionPresenterTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import XCTest
@testable import CodeEdit

final class CompletionPresenterTests: XCTestCase {
    private func candidate(source: CompletionSource) -> CompletionCandidate {
        CompletionCandidate(
            id: UUID().uuidString,
            label: "foo",
            filterText: "foo",
            kind: .snippet,
            source: source,
            payload: .plain(insertText: "foo")
        )
    }

    func testLSPSourceHasLanguageServerBadge() {
        XCTAssertEqual(CompletionPresenter.badge(for: .lsp)?.accessibilityLabel, "Language server")
    }

    func testSnippetKeywordAndAIEachHaveADistinctBadge() {
        XCTAssertEqual(CompletionPresenter.badge(for: .snippet)?.accessibilityLabel, "Snippet")
        XCTAssertEqual(CompletionPresenter.badge(for: .keyword)?.accessibilityLabel, "Keyword")
        XCTAssertEqual(CompletionPresenter.badge(for: .ai)?.accessibilityLabel, "AI suggestion")
    }

    @MainActor
    func testPresentWrapsEachCandidateAndKeepsOrder() {
        let candidates = [candidate(source: .lsp), candidate(source: .ai)]
        let entries = CompletionPresenter.present(candidates)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].badge?.accessibilityLabel, "Language server")
        XCTAssertEqual(entries[1].badge?.accessibilityLabel, "AI suggestion")
    }
}
