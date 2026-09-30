//
//  ProjectEditorUITests.swift
//  CodeEditUITests
//
//  Created by CodeEdit contributors on 9/30/26.
//

import XCTest

/// Selecting the workspace root in the project navigator opens the project editor tab.
final class ProjectEditorUITests: XCTestCase {
    var app: XCUIApplication!
    var window: XCUIElement!
    var navigator: XCUIElement!
    var path: String!
    var projectName: String!

    override func setUp() async throws {
        try await MainActor.run {
            // The CMake project must exist before the workspace opens.
            path = try tempProjectPath()
            projectName = URL(fileURLWithPath: path).lastPathComponent
            try """
            cmake_minimum_required(VERSION 3.21)
            project(Sample VERSION 1.2 LANGUAGES C CXX)
            add_executable(sample main.cpp)
            """.write(toFile: path + "/CMakeLists.txt", atomically: true, encoding: .utf8)
            try "int main() { return 0; }\n".write(toFile: path + "/main.cpp", atomically: true, encoding: .utf8)

            app = XCUIApplication()
            app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--open", path]
            app.launch()

            window = Query.getWindow(app)
            XCTAssertTrue(window.waitForExistence(timeout: 5), "Window not found")
            navigator = Query.Window.getProjectNavigator(window)
            XCTAssertTrue(navigator.exists, "Navigator not found")
        }
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSelectingRootOpensProjectEditorInsteadOfRenaming() throws {
        let rootRow = Query.Navigator.getProjectNavigatorRow(fileTitle: projectName, navigator)
        XCTAssertTrue(rootRow.waitForExistence(timeout: 2), "Root row not found")
        rootRow.click()

        let editor = window.descendants(matching: .any).matching(identifier: "ProjectEditor").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "Project editor did not open")
        attachScreenshot("Toolchain")

        // Clicking the selected root again used to begin renaming the workspace folder.
        rootRow.click()
        sleep(1)
        app.typeKey("a", modifierFlags: .command)
        app.typeText("renamed\r")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "The workspace folder was renamed")

        let panes = window.descendants(matching: .any).matching(identifier: "ProjectEditorPanePicker").firstMatch
        panes.radioButtons["Build Settings"].click()
        XCTAssertTrue(window.descendants(matching: .any)["CMakeBuildConfiguration"].waitForExistence(timeout: 2))
        attachScreenshot("Build Settings")

        panes.radioButtons["CMake Variables"].click()
        let variables = window.descendants(matching: .any).matching(identifier: "CMakeVariables").firstMatch
        XCTAssertTrue(variables.waitForExistence(timeout: 2))
        variables.buttons["Add"].click()
        app.typeText("-DBUILD_TESTING=ON\r")
        let command = window.descendants(matching: .any).matching(identifier: "CMakeConfigureCommand").firstMatch
        XCTAssertTrue(command.waitForExistence(timeout: 2))
        let predicate = NSPredicate(format: "value CONTAINS '-DBUILD_TESTING=ON'")
        expectation(for: predicate, evaluatedWith: command)
        waitForExpectations(timeout: 3)
        attachScreenshot("CMake Variables")

        let settingsFile = path + "/.codeedit/cmake-settings.json"
        let saved = expectation(description: "settings saved")
        DispatchQueue.global().async {
            for _ in 0..<50 {
                if let contents = try? String(contentsOfFile: settingsFile, encoding: .utf8),
                   contents.contains("BUILD_TESTING") {
                    saved.fulfill()
                    return
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        wait(for: [saved], timeout: 6)

        panes.radioButtons["Run / Debug"].click()
        XCTAssertTrue(window.descendants(matching: .any)["CMakeRunTarget"].waitForExistence(timeout: 2))
        attachScreenshot("Run Debug")
    }
}
