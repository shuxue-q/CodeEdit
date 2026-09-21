//
//  ActivityViewerXcodeUITests.swift
//  CodeEditTests
//
//  Created by CodeEdit on 9/17/26.
//

import XCTest
import SwiftUI
@testable import CodeEdit

@MainActor
final class ActivityViewerXcodeUITests: XCTestCase {
    var workspaceSettingsManager: CEWorkspaceSettings!
    var taskNotificationHandler: TaskNotificationHandler!
    var taskManager: TaskManager!

    override func setUp() {
        super.setUp()
        let url = URL(fileURLWithPath: "/tmp")
        workspaceSettingsManager = CEWorkspaceSettings(workspaceURL: url)
        taskNotificationHandler = TaskNotificationHandler()
        taskManager = TaskManager(workspaceSettings: workspaceSettingsManager.settings, workspaceURL: url)
    }

    override func tearDown() {
        workspaceSettingsManager = nil
        taskNotificationHandler = nil
        taskManager = nil
        super.tearDown()
    }

    func testActivityViewerInitialization() {
        let viewer = ActivityViewer(
            workspaceFileManager: nil,
            workspaceSettingsManager: workspaceSettingsManager,
            taskManager: taskManager,
            workspace: nil
        )
        XCTAssertNotNil(viewer)
    }

    func testXcodeCapsuleContainerProperties() {
        let container = XcodeCapsuleContainer(height: 26, horizontalPadding: 8) {
            Text("Test")
        }
        XCTAssertEqual(container.height, 26)
        XCTAssertEqual(container.horizontalPadding, 8)
    }

    func testEditorManagerNavigationHistory() {
        let editorManager = EditorManager()
        let editor = editorManager.activeEditor

        XCTAssertTrue(editor.history.isEmpty)
        XCTAssertEqual(editor.historyOffset, 0)

        let file1 = CEWorkspaceFile(url: URL(fileURLWithPath: "/tmp/file1.swift"))
        let file2 = CEWorkspaceFile(url: URL(fileURLWithPath: "/tmp/file2.swift"))
        editor.history = [file1, file2]
        editor.historyOffset = 0

        // At offset 0, can go back (higher index in history)
        XCTAssertTrue(editor.historyOffset < editor.history.count - 1)
        // At offset 0, cannot go forward
        XCTAssertFalse(editor.historyOffset > 0)

        editor.goBackInHistory()
        XCTAssertEqual(editor.historyOffset, 1)
        XCTAssertTrue(editor.historyOffset > 0)

        editor.goForwardInHistory()
        XCTAssertEqual(editor.historyOffset, 0)
    }

    func testProjectNameResolution() {
        workspaceSettingsManager.settings.project.projectName = "MyCustomProject"
        XCTAssertEqual(workspaceSettingsManager.settings.project.projectName, "MyCustomProject")

        workspaceSettingsManager.settings.project.projectName = ""
        XCTAssertTrue(workspaceSettingsManager.settings.project.projectName.isEmpty)
    }

    func testActivityStatusReadyWhenIdle() {
        XCTAssertEqual(ActivityStatusResolver.status(ActivityStatusInput()), "Ready")
    }

    func testActivityStatusRunningTask() {
        XCTAssertEqual(
            ActivityStatusResolver.status(ActivityStatusInput(runningTaskName: "AVX")),
            "Running AVX"
        )
    }

    func testActivityStatusCMakeOutcomes() {
        XCTAssertEqual(
            ActivityStatusResolver.status(ActivityStatusInput(cmakeOutcome: .success)),
            "Build Succeeded"
        )
        XCTAssertEqual(
            ActivityStatusResolver.status(ActivityStatusInput(cmakeOutcome: .failed(exitCode: 1))),
            "Build Failed"
        )
        XCTAssertEqual(
            ActivityStatusResolver.status(
                ActivityStatusInput(cmakeIsBuilding: true, cmakeStatusText: "Building target aic")
            ),
            "Building target aic"
        )
    }

    func testActivityStatusFinishedTask() {
        XCTAssertEqual(
            ActivityStatusResolver.status(ActivityStatusInput(finishedTaskName: "AVX")),
            "Finished running AVX"
        )
    }

    func testSystemSymbolIntegrity() {
        let requiredSymbols = [
            "chevron.left",
            "chevron.right",
            "play.fill",
            "stop.fill",
            "hammer.fill",
            "plus.bubble",
            "laptopcomputer",
            "exclamationmark.triangle.fill",
            "plus.rectangle.on.rectangle",
            "slider.horizontal.below.rectangle",
            "square.stack",
            "square.grid.2x2",
            "arrow.left.arrow.right",
            "sidebar.trailing"
        ]

        for symbol in requiredSymbols {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            XCTAssertNotNil(image, "Symbol \(symbol) must exist in macOS SF Symbols catalog")
        }
    }

    func testEditorFocusModeToggling() {
        let editorManager = EditorManager()
        let editor = editorManager.activeEditor

        XCTAssertFalse(editorManager.isFocusingActiveEditor)
        editorManager.toggleFocusingEditor(from: editor)
        XCTAssertTrue(editorManager.isFocusingActiveEditor)
        editorManager.toggleFocusingEditor(from: editor)
        XCTAssertFalse(editorManager.isFocusingActiveEditor)
    }

    func testXcodeIssuesCapsulesStandalone() {
        let warnings = XcodeWarningsCapsule(workspace: nil)
        let errors = XcodeErrorsCapsule(workspace: nil)
        XCTAssertNotNil(warnings)
        XCTAssertNotNil(errors)
    }

    func testXcodeAssistantButtonStandalone() {
        let button = XcodeAssistantButton()
        XCTAssertNotNil(button)
    }

    func testXcodeInspectorToggleCapsuleStandalone() {
        let capsule = XcodeInspectorToggleCapsule()
        XCTAssertNotNil(capsule)
    }

    func testStopIsDisabledWhenIdle() {
        XCTAssertFalse(StopTaskToolbarButton.isStopEnabled(selectedStatus: nil, cmakeIsBuilding: false))
        XCTAssertFalse(StopTaskToolbarButton.isStopEnabled(selectedStatus: .notRunning, cmakeIsBuilding: false))
        XCTAssertFalse(StopTaskToolbarButton.isStopEnabled(selectedStatus: .finished, cmakeIsBuilding: false))
    }

    func testStopIsEnabledWhileTaskOrCMakeRuns() {
        XCTAssertTrue(StopTaskToolbarButton.isStopEnabled(selectedStatus: .running, cmakeIsBuilding: false))
        XCTAssertTrue(StopTaskToolbarButton.isStopEnabled(selectedStatus: .notRunning, cmakeIsBuilding: true))
        XCTAssertTrue(StopTaskToolbarButton.isStopEnabled(selectedStatus: .running, cmakeIsBuilding: true))
    }

    func testRunControlsCapsuleConstructs() {
        let capsule = XcodeRunControlsCapsule(taskManager: taskManager)
        XCTAssertNotNil(capsule)
        // Xcode's Run/Stop NSSegmentedControl is play-leading, stop-trailing.
        // The capsule body hosts StartTaskToolbarButton then StopTaskToolbarButton.
        XCTAssertEqual(XcodeRunControlsCapsule.leadingControlLabel, "Run")
        XCTAssertEqual(XcodeRunControlsCapsule.trailingControlLabel, "Stop")
    }
}
