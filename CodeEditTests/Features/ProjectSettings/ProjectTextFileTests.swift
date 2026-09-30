//
//  ProjectTextFileTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 9/30/26.
//

import XCTest
@testable import CodeEdit

@MainActor
final class ProjectTextFileTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectTextFileTests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
    }

    func testMissingFileIsCreatedOnSaveWithParentFolders() throws {
        let url = root.appending(path: ".codeedit/nested/config.json")
        let file = ProjectTextFile(url: url, displayPath: ".codeedit/nested/config.json")
        XCTAssertFalse(file.exists)
        XCTAssertEqual(file.text, "")

        file.text = "{}\n"
        XCTAssertTrue(file.hasUnsavedChanges)
        var didSave = false
        file.didSave = { didSave = true }
        file.save()

        XCTAssertTrue(file.exists)
        XCTAssertFalse(file.hasUnsavedChanges)
        XCTAssertTrue(didSave)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{}\n")
    }

    func testRevertDiscardsEdits() throws {
        let url = root.appending(path: ".gitignore")
        try "build/\n".write(to: url, atomically: true, encoding: .utf8)
        let file = ProjectTextFile(url: url, displayPath: ".gitignore")
        file.text = "build/\n*.o\n"
        file.revert()
        XCTAssertEqual(file.text, "build/\n")
        XCTAssertFalse(file.hasUnsavedChanges)
    }

    func testExternalChangeReloadsWhenClean() throws {
        let url = root.appending(path: ".gitignore")
        try "build/\n".write(to: url, atomically: true, encoding: .utf8)
        let file = ProjectTextFile(url: url, displayPath: ".gitignore")

        try writeLater("build/\n.cache/\n", to: url)
        file.checkForExternalChanges()

        XCTAssertEqual(file.text, "build/\n.cache/\n")
        XCTAssertFalse(file.changedOnDisk)
    }

    func testExternalChangeKeepsUnsavedEdits() throws {
        let url = root.appending(path: ".gitignore")
        try "build/\n".write(to: url, atomically: true, encoding: .utf8)
        let file = ProjectTextFile(url: url, displayPath: ".gitignore")
        file.text = "mine\n"

        try writeLater("theirs\n", to: url)
        file.checkForExternalChanges()

        XCTAssertEqual(file.text, "mine\n")
        XCTAssertTrue(file.changedOnDisk)

        file.revert()
        XCTAssertEqual(file.text, "theirs\n")
        XCTAssertFalse(file.changedOnDisk)
    }

    func testDeletedFileReadsAsMissing() throws {
        let url = root.appending(path: ".clang-format")
        try "BasedOnStyle: LLVM\n".write(to: url, atomically: true, encoding: .utf8)
        let file = ProjectTextFile(url: url, displayPath: ".clang-format")
        try FileManager.default.removeItem(at: url)
        file.checkForExternalChanges()
        XCTAssertFalse(file.exists)
        XCTAssertEqual(file.text, "")
    }

    /// Writes with a modification date distinct from the previous write.
    private func writeLater(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
    }
}
