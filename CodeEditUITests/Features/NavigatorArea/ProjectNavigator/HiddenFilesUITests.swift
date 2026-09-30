//
//  HiddenFilesUITests.swift
//  CodeEditUITests
//
//  Created by CodeEdit contributors on 9/30/26.
//

import XCTest

/// Dotfiles are hidden from the project navigator and edited from the project editor's
/// Version Control and Project Files sections instead.
final class HiddenFilesUITests: XCTestCase {
    var app: XCUIApplication!
    var window: XCUIElement!
    var navigator: XCUIElement!
    var path: String!
    var projectName: String!

    override func setUp() async throws {
        try await MainActor.run {
            path = try tempProjectPath()
            projectName = URL(fileURLWithPath: path).lastPathComponent
            try "build/\n".write(toFile: path + "/.gitignore", atomically: true, encoding: .utf8)
            try "BasedOnStyle: LLVM\n".write(toFile: path + "/.clang-format", atomically: true, encoding: .utf8)
            try "int main() { return 0; }\n".write(toFile: path + "/main.cpp", atomically: true, encoding: .utf8)
            try FileManager.default.createDirectory(atPath: path + "/build", withIntermediateDirectories: true)
            try makeRepository()

            app = XCUIApplication()
            app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--open", path]
            app.launch()

            window = Query.getWindow(app)
            XCTAssertTrue(window.waitForExistence(timeout: 5), "Window not found")
            navigator = Query.Window.getProjectNavigator(window)
            XCTAssertTrue(navigator.exists, "Navigator not found")
        }
    }

    /// Writes a minimal repository by hand: the sandboxed test runner cannot run `git`.
    private func makeRepository() throws {
        let git = path + "/.git"
        for folder in ["objects", "refs/heads", "refs/tags"] {
            try FileManager.default.createDirectory(atPath: git + "/" + folder, withIntermediateDirectories: true)
        }
        try "ref: refs/heads/trunk\n".write(toFile: git + "/HEAD", atomically: true, encoding: .utf8)
        try """
        [core]
        \trepositoryformatversion = 0
        \tbare = false
        [remote "origin"]
        \turl = https://example.com/sample.git
        \tfetch = +refs/heads/*:refs/remotes/origin/*

        """.write(toFile: git + "/config", atomically: true, encoding: .utf8)
    }

    private func row(_ title: String) -> XCUIElement {
        Query.Navigator.getProjectNavigatorRow(fileTitle: title, navigator)
    }

    private func element(_ identifier: String) -> XCUIElement {
        window.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func waitForFile(_ file: String, toContain text: String) {
        let saved = expectation(description: "\(file) contains \(text)")
        DispatchQueue.global().async {
            for _ in 0..<50 {
                if let contents = try? String(contentsOfFile: file, encoding: .utf8), contents.contains(text) {
                    saved.fulfill()
                    return
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        wait(for: [saved], timeout: 6)
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDotfilesAreHiddenAndEditableFromProjectEditor() throws {
        XCTAssertTrue(row("main.cpp").waitForExistence(timeout: 3), "Regular files are listed")
        XCTAssertFalse(row(".gitignore").exists, ".gitignore is listed")
        XCTAssertFalse(row(".clang-format").exists, ".clang-format is listed")
        XCTAssertFalse(row(".git").exists, ".git is listed")

        row(projectName).click()
        XCTAssertTrue(element("ProjectEditor").waitForExistence(timeout: 3), "Project editor did not open")
        let panes = element("ProjectEditorPanePicker")
        XCTAssertFalse(panes.radioButtons["Toolchain"].exists, "CMake sections shown for a plain folder")

        // Version Control: repository info and the .gitignore editor.
        panes.radioButtons["Version Control"].click()
        let versionControl = element("ProjectEditorVersionControl")
        XCTAssertTrue(versionControl.waitForExistence(timeout: 3))
        XCTAssertTrue(versionControl.staticTexts["trunk"].waitForExistence(timeout: 5), "Branch not shown")
        XCTAssertTrue(versionControl.staticTexts["https://example.com/sample.git"].exists, "Remote not shown")
        let gitignoreText = versionControl.textViews.firstMatch
        XCTAssertTrue(gitignoreText.waitForExistence(timeout: 2))
        XCTAssertEqual(gitignoreText.value as? String, "build/\n")
        gitignoreText.click()
        // Avoid modifier keys: a held Command key turns the typed text into menu shortcuts.
        gitignoreText.typeKey(.downArrow, modifierFlags: [])
        gitignoreText.typeKey(.downArrow, modifierFlags: [])
        gitignoreText.typeText("*.o\n")
        versionControl.buttons["ProjectTextFileSave"].click()
        waitForFile(path + "/.gitignore", toContain: "build/\n*.o\n")
        attachScreenshot("Version Control")

        // A change made on disk reloads the editor when it has no unsaved edits.
        try "build/\n*.o\n.cache/\n".write(toFile: path + "/.gitignore", atomically: true, encoding: .utf8)
        let reloaded = NSPredicate(format: "value CONTAINS '.cache/'")
        expectation(for: reloaded, evaluatedWith: gitignoreText)
        waitForExpectations(timeout: 4)

        // Project Files: exclusions hide more rows; Show Hidden Files brings dotfiles back.
        panes.radioButtons["Project Files"].click()
        let projectFiles = element("ProjectEditorProjectFiles")
        XCTAssertTrue(projectFiles.waitForExistence(timeout: 3))
        XCTAssertTrue(projectFiles.staticTexts[".clang-format"].exists, "Config file not listed")
        XCTAssertTrue(row("build").exists, "build folder should be listed before excluding it")
        element("NavigatorExclusionPatterns").buttons["Add"].click()
        app.typeText("build/\r")
        waitForFile(path + "/.codeedit/settings.json", toContain: "build/")
        let buildHidden = NSPredicate(format: "exists == false")
        expectation(for: buildHidden, evaluatedWith: row("build"))
        waitForExpectations(timeout: 4)

        projectFiles.checkBoxes["Show Hidden Files"].click()
        XCTAssertTrue(row(".gitignore").waitForExistence(timeout: 4), "Show Hidden Files did not list dotfiles")
        XCTAssertTrue(row(".codeedit").exists)
        attachScreenshot("Project Files")
    }
}
