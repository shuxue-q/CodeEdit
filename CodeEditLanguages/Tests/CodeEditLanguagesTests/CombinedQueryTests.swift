//
//  CombinedQueryTests.swift
//  CodeEditLanguages
//
//  Created by CodeEdit on 10.10.26.
//

import XCTest
@testable import CodeEditLanguages

/// The editor highlights with `TreeSitterModel.query(for:)`, which compiles `highlights.scm` together with the
/// parent and every additional query file (folds, indents, injections, locals, tags) as one query. A single unknown
/// node in any of those files silently disables highlighting for the whole language, which the per-file
/// `test_FetchQuery…` tests cannot catch.
final class CombinedQueryTests: XCTestCase {
    /// Languages whose highlighting (including the `variable.assigned` capture) is covered by editor tests.
    private let languages: [TreeSitterLanguage] = [
        .bash, .c, .cpp, .cmake, .go, .java, .javascript, .jsx, .kotlin, .lua, .objc,
        .python, .ruby, .rust, .swift, .tsx, .typescript
    ]

    func test_combinedQueryCompilesForSupportedLanguages() throws {
        for language in languages {
            let query = TreeSitterModel.shared.query(for: language)
            XCTAssertNotNil(query, "\(language) combined query failed to compile")
            XCTAssertNotEqual(query?.patternCount ?? 0, 0, "\(language) combined query has no patterns")
        }
    }

    /// Every edited highlight query declares the assignment target capture.
    func test_assignedVariableCaptureIsDeclared() throws {
        for language in [CodeLanguage.bash, .c, .cmake, .go, .java, .javascript, .kotlin, .lua, .python, .ruby,
                         .rust, .swift] {
            let url = try XCTUnwrap(language.queryURL, "\(language.id) has no highlights query")
            let text = try String(contentsOf: url)
            XCTAssertTrue(text.contains("@variable.assigned"), "\(language.id) lacks @variable.assigned")
        }
    }
}
