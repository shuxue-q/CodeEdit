//
//  TaskManagerGeneratedTasksTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation
import Testing
@testable import CodeEdit

@MainActor
@Suite(.serialized)
struct TaskManagerGeneratedTasksTests {
    private func makeManager(workspace: URL) throws -> TaskManager {
        let settings = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data("{}".utf8))
        return TaskManager(workspaceSettings: settings, workspaceURL: workspace)
    }

    private func task(
        _ name: String,
        command: String,
        action: GeneratedTaskInfo.Action = .shell,
        hotReload: Bool = false
    ) -> GeneratedTask {
        GeneratedTask(
            name: name,
            command: command,
            workingDirectory: ".",
            info: GeneratedTaskInfo(
                action: action,
                toolchain: hotReload ? .flutter : .cmake,
                role: hotReload ? .run : .build,
                group: "Test",
                componentPath: ".",
                outputParser: .flutter,
                supportsHotReload: hotReload
            )
        )
    }

    @Test
    func generatedTasksFollowUserTasksAndKeepTheSelection() throws {
        try withTempDir { root in
            let manager = try makeManager(workspace: root)
            let user = CETask(name: "Mine", command: "true")
            manager.workspaceSettings.tasks.append(user)
            manager.setGeneratedTasks([task("A", command: "true"), task("B", command: "true")])
            #expect(manager.availableTasks.map(\.name) == ["Mine", "A", "B"])

            let second = try #require(manager.generatedTasks.last)
            manager.selectedTaskID = second.id
            // Regenerating with a changed command keeps the stable ID and therefore the selection.
            manager.setGeneratedTasks([task("A", command: "true"), task("B", command: "false")])
            #expect(manager.selectedTaskID == second.id)
            #expect(manager.generatedTasks.last?.command == "false")

            manager.setGeneratedTasks([task("A", command: "true")])
            #expect(manager.selectedTaskID == user.id)
        }
    }

    @Test
    func rerunningATaskUsesItsRegeneratedCommand() async throws {
        Settings.shared.preferences.terminal.shell = .zsh
        try await withTempDir { root in
            let manager = try makeManager(workspace: root)
            // The arithmetic makes the output differ from the echoed command line.
            manager.setGeneratedTasks([task("Build", command: "echo first-$((0+1))")])
            let taskID = try #require(manager.generatedTasks.first?.id)
            manager.executeActiveTask()
            await waitForExpectation(timeout: .seconds(10)) {
                manager.taskStatus(taskID: taskID) == .finished
            } onTimeout: {
                Issue.record("First run did not finish")
            }

            // Settings changed: same task, new command.
            manager.setGeneratedTasks([task("Build", command: "echo second-$((1+1))")])
            manager.executeActiveTask()
            await waitForExpectation(timeout: .seconds(10)) {
                manager.activeTasks[taskID]?.output?.getBufferAsString().contains("second-2") == true
            } onTimeout: {
                Issue.record("The rerun did not use the new command")
            }
        }
    }

    @Test
    func cmakeBuildTaskDrivesTheBuildController() throws {
        try withTempDir { root in
            let manager = try makeManager(workspace: root)
            let workspace = CMakeWorkspace(sourceDirectory: root)
            manager.cmakeBuildController = CMakeBuildController(sourceDirectory: root, workspace: workspace)
            // No tasks at all: Run builds, as before.
            #expect(manager.isCMakeBuildTarget)

            manager.setGeneratedTasks([
                task("Run app", command: "true", hotReload: true),
                task("Build (CMake)", command: "", action: .cmakeBuild)
            ])
            #expect(!manager.isCMakeBuildTarget)
            manager.selectedTaskID = manager.generatedTasks.last?.id
            #expect(manager.isCMakeBuildTarget)
        }
    }

    @Test
    func hotReloadTypesKeysIntoTheRunningTask() async throws {
        Settings.shared.preferences.terminal.shell = .zsh
        try await withTempDir { root in
            let manager = try makeManager(workspace: root)
            manager.diagnosticsStore = TaskDiagnosticsStore()
            // Behaves like `flutter run`: announces its keys, then reacts to r, R and q.
            let fakeFlutterRun = """
            printf 'Flutter run key commands.\\n'; \
            while read -k 1 key; do \
            if [[ $key == q ]]; then echo quitting; exit 0; fi; \
            echo "key:$key"; \
            done
            """
            manager.setGeneratedTasks([task("Run app", command: fakeFlutterRun, hotReload: true)])
            let taskID = try #require(manager.generatedTasks.first?.id)
            #expect(!manager.canHotReload)
            manager.executeActiveTask()

            await waitForExpectation(timeout: .seconds(15)) {
                manager.hotReloadReadyTaskIDs.contains(taskID)
            } onTimeout: {
                Issue.record("The task never announced its hot reload keys.")
            }
            #expect(manager.canHotReload)

            #expect(manager.hotReload())
            await waitForExpectation(timeout: .seconds(5)) {
                manager.activeTasks[taskID]?.output?.getBufferAsString().contains("key:r") == true
            } onTimeout: {
                Issue.record("Hot reload did not reach the task.")
            }

            #expect(manager.hotReload(restart: true))
            await waitForExpectation(timeout: .seconds(5)) {
                manager.activeTasks[taskID]?.output?.getBufferAsString().contains("key:R") == true
            } onTimeout: {
                Issue.record("Hot restart did not reach the task.")
            }

            // Stop quits with `q`, so the run ends cleanly instead of being killed.
            manager.terminateActiveTask()
            await waitForExpectation(timeout: .seconds(8)) {
                manager.taskStatus(taskID: taskID) == .finished
            } onTimeout: {
                Issue.record("The task did not quit: \(manager.taskStatus(taskID: taskID))")
            }
            #expect(!manager.canHotReload)
        }
    }

    @Test
    func generatedTaskOutputBecomesProblems() async throws {
        Settings.shared.preferences.terminal.shell = .zsh
        try await withTempDir { root in
            let manager = try makeManager(workspace: root)
            let store = TaskDiagnosticsStore()
            manager.diagnosticsStore = store
            let command = "printf 'lib/main.dart:3:5: Error: Expected a value.\\n'; exit 1"
            manager.setGeneratedTasks([task("Build app", command: command)])
            let taskID = try #require(manager.generatedTasks.first?.id)
            manager.executeActiveTask()
            await waitForExpectation(timeout: .seconds(15)) {
                manager.taskStatus(taskID: taskID) == .failed
            } onTimeout: {
                Issue.record("The task did not fail: \(manager.taskStatus(taskID: taskID))")
            }
            await waitForExpectation(timeout: .seconds(5)) {
                !store.isEmpty
            } onTimeout: {
                Issue.record("No problem was parsed")
            }
            let diagnostic = try #require(store.all.first)
            #expect(diagnostic.message == "Expected a value.")
            #expect(diagnostic.filePath == root.appending(path: "lib/main.dart").standardizedFileURL.path)
            #expect(diagnostic.line == 3)
        }
    }
}
