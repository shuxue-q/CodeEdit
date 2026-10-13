//
//  HybridProjectUITests.swift
//  CodeEditUITests
//
//  Created by CodeEdit contributors on 10/13/26.
//

import XCTest

/// A workspace combining a Flutter app, a CMake project and a Cargo workspace gets the Overview,
/// Flutter, Rust and C++ sections, and its generated tasks in the scheme menu.
final class HybridProjectUITests: XCTestCase {
    var app: XCUIApplication!
    var window: XCUIElement!
    var navigator: XCUIElement!
    var projectName: String!

    private static let files: [String: String] = [
        "pubspec.yaml": "name: hybrid_app\nversion: 1.0.0\ndependencies:\n  flutter:\n    sdk: flutter\n",
        ".metadata": "project_type: app\n",
        "lib/main.dart": "void main() {}\n",
        "macos/Runner/AppDelegate.swift": "",
        "hook/build.dart": "// runs cmake\n",
        "CMakeLists.txt": "cmake_minimum_required(VERSION 3.21)\nproject(core LANGUAGES CXX)\nadd_subdirectory(cpp)\n",
        "cpp/CMakeLists.txt": "# links rust/kernel, built with cargo\n",
        "rust/Cargo.toml": "[workspace]\nmembers = [\"kernel\"]\n",
        "rust/kernel/Cargo.toml": "[package]\nname = \"kernel\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
        "rust/kernel/src/lib.rs": "",
        "rust/kernel/src/main.rs": "fn main() {}\n"
    ]

    override func setUp() async throws {
        try await MainActor.run {
            let path = try tempProjectPath()
            projectName = URL(fileURLWithPath: path).lastPathComponent
            for (relativePath, contents) in Self.files {
                let url = URL(fileURLWithPath: path).appending(path: relativePath)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try contents.write(to: url, atomically: true, encoding: .utf8)
            }
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

    private func element(_ identifier: String) -> XCUIElement {
        window.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func testProjectEditorAndSchemeMenuShowAllToolchains() throws {
        let rootRow = Query.Navigator.getProjectNavigatorRow(fileTitle: projectName, navigator)
        XCTAssertTrue(rootRow.waitForExistence(timeout: 2), "Root row not found")
        rootRow.click()
        XCTAssertTrue(element("ProjectEditor").waitForExistence(timeout: 3), "Project editor did not open")

        let panes = element("ProjectEditorPanePicker")
        XCTAssertTrue(panes.radioButtons["Overview"].waitForExistence(timeout: 10), "No Overview section")
        panes.radioButtons["Overview"].click()
        XCTAssertTrue(element("ProjectEditorOverview").waitForExistence(timeout: 3))
        XCTAssertTrue(window.staticTexts["kernel"].waitForExistence(timeout: 5), "Cargo workspace not listed")
        attachScreenshot("Overview")

        panes.radioButtons["Flutter"].click()
        XCTAssertTrue(element("ProjectEditorFlutter").waitForExistence(timeout: 3))
        attachScreenshot("Flutter")

        panes.radioButtons["Rust"].click()
        XCTAssertTrue(element("ProjectEditorRust").waitForExistence(timeout: 3))
        attachScreenshot("Rust")

        panes.radioButtons["C++"].click()
        XCTAssertTrue(element("ProjectEditorCMakePanePicker").waitForExistence(timeout: 3))
        attachScreenshot("C++")

        let scheme = app.descendants(matching: .any).matching(identifier: "SchemeDestinationCapsule").firstMatch
        XCTAssertTrue(scheme.waitForExistence(timeout: 3), "Scheme capsule not found")
        scheme.click()
        XCTAssertTrue(app.staticTexts["Run hybrid_app"].waitForExistence(timeout: 5), "Flutter run task missing")
        XCTAssertTrue(app.staticTexts["Cargo Build"].exists, "Cargo build task missing")
        XCTAssertTrue(app.staticTexts["Build core (CMake)"].exists, "CMake build task missing")
        attachScreenshot("Scheme Menu")
    }
}
