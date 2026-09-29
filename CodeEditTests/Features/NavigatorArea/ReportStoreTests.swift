//
//  ReportStoreTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 9/22/26.
//

import Foundation
import Testing
@testable import CodeEdit

@MainActor
@Suite
final class ReportStoreTests {
    private func makeRecord(
        kind: ReportRecord.Kind = .task,
        title: String = "Record",
        status: ReportRecord.Status = .succeeded
    ) -> ReportRecord {
        ReportRecord(kind: kind, title: title, date: Date(), status: status)
    }

    private func makeDiagnostic(_ severity: CMakeBuildDiagnostic.Severity) -> CMakeBuildDiagnostic {
        CMakeBuildDiagnostic(severity: severity, message: "message")
    }

    @Test
    func addRecordInsertsNewestFirst() {
        let store = ReportStore(workspaceURL: nil)
        let first = makeRecord(title: "First")
        let second = makeRecord(title: "Second")
        store.addRecord(first)
        store.addRecord(second)
        #expect(store.records.map(\.id) == [second.id, first.id])
    }

    @Test
    func recordsAreCappedAtMaximumRecords() {
        let store = ReportStore(workspaceURL: nil)
        var added: [ReportRecord] = []
        for index in 0..<(ReportStore.maximumRecords + 5) {
            let record = makeRecord(title: "Record \(index)")
            added.append(record)
            store.addRecord(record)
        }
        #expect(store.records.count == ReportStore.maximumRecords)
        #expect(store.records.first?.id == added.last?.id)
        // The five oldest records were dropped.
        #expect(store.records.last?.id == added[5].id)
        #expect(!store.records.contains(added[0]))
    }

    @Test
    func recordsPersistAcrossStoreInstances() throws {
        try withTempDir { dir in
            let first = ReportStore(workspaceURL: dir)
            let build = ReportRecord(
                kind: .build,
                title: "Build",
                date: Date(),
                duration: 1.5,
                status: .failed,
                errorCount: 2,
                warningCount: 1,
                diagnostics: [makeDiagnostic(.error), makeDiagnostic(.error), makeDiagnostic(.warning)]
            )
            let task = makeRecord(kind: .task, title: "My Task", status: .succeeded)
            first.addRecord(build)
            first.addRecord(task)

            let second = ReportStore(workspaceURL: dir)
            #expect(second.records.count == 2)
            #expect(second.records.map(\.id) == [task.id, build.id])
            let loadedBuild = try #require(second.records.last)
            #expect(loadedBuild.kind == .build)
            #expect(loadedBuild.title == "Build")
            #expect(loadedBuild.status == .failed)
            #expect(loadedBuild.errorCount == 2)
            #expect(loadedBuild.warningCount == 1)
            #expect(loadedBuild.diagnostics.count == 3)
            let loadedTask = try #require(second.records.first)
            #expect(loadedTask.kind == .task)
            #expect(loadedTask.title == "My Task")
            #expect(loadedTask.status == .succeeded)
        }
    }

    @Test
    func recordBuildMapsOutcomesAndCountsDiagnostics() {
        let store = ReportStore(workspaceURL: nil)
        let diagnostics = [
            makeDiagnostic(.error),
            makeDiagnostic(.warning),
            makeDiagnostic(.warning),
            makeDiagnostic(.note)
        ]
        store.recordBuild(outcome: .success, diagnostics: diagnostics, log: "log output", startedAt: nil)
        #expect(store.records.count == 1)
        let record = store.records[0]
        #expect(record.kind == .build)
        #expect(record.title == "Build")
        #expect(record.status == .succeeded)
        #expect(record.errorCount == 1)
        #expect(record.warningCount == 2)
        #expect(record.diagnostics.count == 4)
        #expect(record.logExcerpt == "log output")
        #expect(record.duration == nil)

        store.recordBuild(outcome: .cancelled, diagnostics: [], log: "", startedAt: Date())
        #expect(store.records.first?.status == .cancelled)
        #expect(store.records.first?.logExcerpt == nil)

        store.recordBuild(outcome: .failed(exitCode: 1), diagnostics: [], log: "x", startedAt: nil)
        #expect(store.records.first?.status == .failed)
    }

    @Test
    func recordBuildIgnoresNoneOutcome() {
        let store = ReportStore(workspaceURL: nil)
        store.recordBuild(outcome: .none, diagnostics: [], log: "log", startedAt: nil)
        #expect(store.records.isEmpty)
    }

    @Test
    func recordBuildTruncatesLogExcerpt() {
        let store = ReportStore(workspaceURL: nil)
        let log = String(repeating: "a", count: ReportStore.logExcerptCharacterLimit + 100)
        store.recordBuild(outcome: .success, diagnostics: [], log: log, startedAt: nil)
        let excerpt = store.records.first?.logExcerpt
        #expect(excerpt?.count == ReportStore.logExcerptCharacterLimit)
        #expect(excerpt == String(log.suffix(ReportStore.logExcerptCharacterLimit)))
    }

    @Test
    func recordTaskRecordsKindTitleStatusAndDuration() {
        let store = ReportStore(workspaceURL: nil)
        store.recordTask(name: "Build All", status: .failed, duration: 12.5)
        #expect(store.records.count == 1)
        let record = store.records[0]
        #expect(record.kind == .task)
        #expect(record.title == "Build All")
        #expect(record.status == .failed)
        #expect(record.duration == 12.5)
    }

    @Test
    func removeDeletesRecordAndPersists() throws {
        try withTempDir { dir in
            let store = ReportStore(workspaceURL: dir)
            let keep = makeRecord(title: "Keep")
            let drop = makeRecord(title: "Drop")
            store.addRecord(keep)
            store.addRecord(drop)
            store.remove(drop)
            #expect(store.records.map(\.id) == [keep.id])

            let reloaded = ReportStore(workspaceURL: dir)
            #expect(reloaded.records.map(\.id) == [keep.id])
        }
    }

    @Test
    func clearAllEmptiesRecordsAndPersists() throws {
        try withTempDir { dir in
            let store = ReportStore(workspaceURL: dir)
            store.addRecord(makeRecord())
            store.addRecord(makeRecord())
            store.clearAll()
            #expect(store.records.isEmpty)

            let reloaded = ReportStore(workspaceURL: dir)
            #expect(reloaded.records.isEmpty)
        }
    }

    @Test
    func recordsDebugSessionOnlyForTheLaunchingWorkspace() {
        let workspace = URL(fileURLWithPath: "/tmp/project")
        let other = URL(fileURLWithPath: "/tmp/other")
        #expect(ReportStore.recordsDebugSession(storeWorkspace: workspace, sessionWorkspace: workspace))
        #expect(!ReportStore.recordsDebugSession(storeWorkspace: workspace, sessionWorkspace: other))
        #expect(!ReportStore.recordsDebugSession(storeWorkspace: workspace, sessionWorkspace: nil))
        #expect(!ReportStore.recordsDebugSession(storeWorkspace: nil, sessionWorkspace: workspace))
    }

    @Test
    func recordDebugSessionKeepsTheReportedStatus() {
        let store = ReportStore(workspaceURL: nil)
        let started = Date().addingTimeInterval(-4)
        store.recordDebugSession(startedAt: started, status: .failed)
        #expect(store.records.count == 1)
        #expect(store.records[0].kind == .debug)
        #expect(store.records[0].status == .failed)
        #expect(store.records[0].date == started)

        store.recordDebugSession(startedAt: Date(), status: .cancelled)
        #expect(store.records[0].status == .cancelled)
    }

    @Test
    func nilWorkspaceURLKeepsRecordsInMemoryOnly() {
        let store = ReportStore(workspaceURL: nil)
        store.addRecord(makeRecord())
        store.recordTask(name: "Task", status: .succeeded, duration: nil)
        store.clearAll()
        #expect(store.records.isEmpty)
    }
}
