//
//  CMakeTests.swift
//  CodeEditLanguages
//

import XCTest
@testable import CodeEditLanguages
import SwiftTreeSitter

final class CMakeTests: XCTestCase {
    func testDetectsCMakeFileExtension() {
        let url = URL(fileURLWithPath: "/path/to/toolchain.cmake")

        XCTAssertEqual(CodeLanguage.detectLanguageFrom(url: url).id, .cmake)
    }

    func testDetectsCMakeListsFileName() {
        let url = URL(fileURLWithPath: "/path/to/CMakeLists.txt")

        XCTAssertEqual(CodeLanguage.detectLanguageFrom(url: url).id, .cmake)
    }

    func testCMakeHighlightQueryLoads() throws {
        let query = try XCTUnwrap(TreeSitterModel.shared.query(for: .cmake))

        XCTAssertNotEqual(query.patternCount, 0)
    }
}
