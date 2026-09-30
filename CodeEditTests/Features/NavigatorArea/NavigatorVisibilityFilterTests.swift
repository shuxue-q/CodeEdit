//
//  NavigatorVisibilityFilterTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 9/30/26.
//

import XCTest
@testable import CodeEdit

final class NavigatorVisibilityFilterTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/tmp/Project/", isDirectory: true)

    private func filter(showHidden: Bool = false, patterns: [String] = []) -> NavigatorVisibilityFilter {
        var settings = NavigatorSettings()
        settings.showHiddenFiles = showHidden
        settings.excludedPatterns = patterns
        return NavigatorVisibilityFilter(settings: settings, rootURL: root)
    }

    private func url(_ path: String) -> URL {
        root.appending(path: path)
    }

    func testDotfilesAreHiddenByDefault() {
        let filter = filter()
        XCTAssertFalse(filter.isVisible(url(".git"), isFolder: true))
        XCTAssertFalse(filter.isVisible(url(".codeedit"), isFolder: true))
        XCTAssertFalse(filter.isVisible(url(".clang-format"), isFolder: false))
        XCTAssertFalse(filter.isVisible(url("src/.cache"), isFolder: true))
        XCTAssertTrue(filter.isVisible(url("src/main.cpp"), isFolder: false))
        XCTAssertTrue(filter.isVisible(url("CMakeLists.txt"), isFolder: false))
    }

    func testShowHiddenFilesShowsDotfiles() {
        let filter = filter(showHidden: true)
        XCTAssertTrue(filter.isVisible(url(".git"), isFolder: true))
        XCTAssertTrue(filter.isVisible(url(".clang-format"), isFolder: false))
    }

    func testNamePatternsMatchAnywhere() {
        let filter = filter(patterns: ["*.o", "build/"])
        XCTAssertFalse(filter.isVisible(url("main.o"), isFolder: false))
        XCTAssertFalse(filter.isVisible(url("src/lib/util.o"), isFolder: false))
        XCTAssertFalse(filter.isVisible(url("build"), isFolder: true))
        XCTAssertFalse(filter.isVisible(url("sub/build"), isFolder: true))
        // A trailing slash only matches folders.
        XCTAssertTrue(filter.isVisible(url("build"), isFolder: false))
        XCTAssertTrue(filter.isVisible(url("main.cpp"), isFolder: false))
    }

    func testPathPatternsMatchFromTheRoot() {
        let filter = filter(patterns: ["docs/*.png", "/third_party"])
        XCTAssertFalse(filter.isVisible(url("docs/logo.png"), isFolder: false))
        XCTAssertTrue(filter.isVisible(url("docs/images/logo.png"), isFolder: false))
        XCTAssertTrue(filter.isVisible(url("other/docs/logo.png"), isFolder: false))
        XCTAssertFalse(filter.isVisible(url("third_party"), isFolder: true))
    }

    func testBlankPatternsAreIgnored() {
        let filter = filter(patterns: ["", "  ", "/"])
        XCTAssertTrue(filter.isVisible(url("main.cpp"), isFolder: false))
    }
}
