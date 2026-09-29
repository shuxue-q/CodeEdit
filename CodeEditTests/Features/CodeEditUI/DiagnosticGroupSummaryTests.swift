//
//  DiagnosticGroupSummaryTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 9/27/26.
//

import Testing
@testable import CodeEdit

@Suite
struct DiagnosticGroupSummaryTests {
    @Test
    func countsNotesSeparatelyAndUsesSingularLabels() {
        #expect(DiagnosticGroupSummary.text(errors: 0, warnings: 0, notes: 0) == "")
        #expect(DiagnosticGroupSummary.text(errors: 1, warnings: 0, notes: 0) == "1 error")
        #expect(DiagnosticGroupSummary.text(errors: 2, warnings: 0, notes: 0) == "2 errors")
        #expect(DiagnosticGroupSummary.text(errors: 0, warnings: 1, notes: 0) == "1 warning")
        #expect(DiagnosticGroupSummary.text(errors: 0, warnings: 0, notes: 2) == "2 notes")
        #expect(
            DiagnosticGroupSummary.text(errors: 1, warnings: 1, notes: 1)
            == "1 error, 1 warning, 1 note"
        )
    }
}
