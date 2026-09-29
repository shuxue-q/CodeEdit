//
//  ReportStore.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/22/26.
//

import Foundation
import Combine

/// A single entry in the report navigator: a past build, run, debug session, or task.
struct ReportRecord: Identifiable, Codable, Hashable {
    /// What produced the report.
    enum Kind: String, Codable {
        case build
        case run
        case debug
        case task
    }

    /// How the recorded operation ended.
    enum Status: String, Codable {
        case succeeded
        case failed
        case cancelled
    }

    let id: UUID
    var kind: Kind
    var title: String
    /// When the recorded operation started.
    var date: Date
    var duration: TimeInterval?
    var status: Status
    var errorCount: Int
    var warningCount: Int
    /// Diagnostics captured during the operation; empty for non-build reports.
    var diagnostics: [CMakeBuildDiagnostic]
    /// The tail of the raw build log, kept for build reports only.
    var logExcerpt: String?

    init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        date: Date,
        duration: TimeInterval? = nil,
        status: Status,
        errorCount: Int = 0,
        warningCount: Int = 0,
        diagnostics: [CMakeBuildDiagnostic] = [],
        logExcerpt: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.date = date
        self.duration = duration
        self.status = status
        self.errorCount = errorCount
        self.warningCount = warningCount
        self.diagnostics = diagnostics
        self.logExcerpt = logExcerpt
    }
}

/// Per-workspace history of builds, runs, debug sessions, and tasks shown in the
/// report navigator.
///
/// Records are kept newest-first, capped at ``maximumRecords``, and persisted to
/// `<workspace>/.codeedit/reports.json` after every mutation. Debug sessions are
/// recorded automatically by observing ``DebugService``'s session state.
@MainActor
final class ReportStore: ObservableObject {
    /// The maximum number of records retained; older records are dropped.
    static let maximumRecords = 50

    /// The maximum number of log characters kept per build record.
    static let logExcerptCharacterLimit = 20_000

    /// The recorded history, newest first.
    @Published private(set) var records: [ReportRecord] = []

    /// `<workspace>/.codeedit/reports.json`, or `nil` for workspaces without a URL
    /// (records then live in memory only).
    private let workspaceURL: URL?
    private let fileURL: URL?

    private var debugSessionCancellable: AnyCancellable?
    private var debugSessionStartDate: Date?

    /// Creates the store for a workspace, loading any persisted history and subscribing
    /// to debug session state changes.
    /// - Parameter workspaceURL: The workspace's folder URL, used to locate
    ///   `<workspace>/.codeedit/reports.json`. `nil` disables persistence.
    init(workspaceURL: URL?) {
        self.workspaceURL = workspaceURL
        self.fileURL = workspaceURL?
            .appending(path: ".codeedit", directoryHint: .isDirectory)
            .appending(path: "reports")
            .appendingPathExtension("json")
        load()

        debugSessionCancellable = DebugService.shared.$sessionState
            .sink { [weak self] state in
                self?.handleDebugSessionState(state)
            }
    }

    deinit {
        debugSessionCancellable?.cancel()
    }

    // MARK: - Recording

    /// Appends a record, keeping the store newest-first and within ``maximumRecords``,
    /// then persists.
    func addRecord(_ record: ReportRecord) {
        records.insert(record, at: 0)
        if records.count > Self.maximumRecords {
            records.removeLast(records.count - Self.maximumRecords)
        }
        persist()
    }

    /// Records a finished CMake build. Builds that never ran (`.none`) are ignored.
    /// - Parameters:
    ///   - outcome: The build's final outcome.
    ///   - diagnostics: The diagnostics collected during the build.
    ///   - log: The build's raw combined stdout/stderr; only the last
    ///     ``logExcerptCharacterLimit`` characters are kept.
    ///   - startedAt: When the build started, used to compute the duration.
    func recordBuild(
        outcome: CMakeBuildController.Outcome,
        diagnostics: [CMakeBuildDiagnostic],
        log: String,
        startedAt: Date?
    ) {
        let status: ReportRecord.Status
        switch outcome {
        case .success: status = .succeeded
        case .failed: status = .failed
        case .cancelled: status = .cancelled
        case .none: return
        }
        addRecord(ReportRecord(
            kind: .build,
            title: "Build",
            date: startedAt ?? Date(),
            duration: startedAt.map { Date().timeIntervalSince($0) },
            status: status,
            errorCount: diagnostics.reduce(0) { $0 + ($1.severity == .error ? 1 : 0) },
            warningCount: diagnostics.reduce(0) { $0 + ($1.severity == .warning ? 1 : 0) },
            diagnostics: diagnostics,
            logExcerpt: log.isEmpty ? nil : String(log.suffix(Self.logExcerptCharacterLimit))
        ))
    }

    /// Records a finished workspace task.
    /// - Parameters:
    ///   - name: The task's name.
    ///   - status: How the task ended.
    ///   - duration: How long the task ran, when known.
    func recordTask(name: String, status: ReportRecord.Status, duration: TimeInterval?) {
        addRecord(ReportRecord(
            kind: .task,
            title: name,
            date: Date(),
            duration: duration,
            status: status
        ))
    }

    // MARK: - Managing records

    /// Removes a single record and persists.
    func remove(_ record: ReportRecord) {
        records.removeAll { $0.id == record.id }
        persist()
    }

    /// Removes all records and persists.
    func clearAll() {
        records = []
        persist()
    }

    // MARK: - Debug sessions

    /// Whether a debug session owned by `sessionWorkspace` should be written into the
    /// store for `storeWorkspace`. Other open projects subscribe to the same shared
    /// service and must not record a session they did not launch.
    static func recordsDebugSession(storeWorkspace: URL?, sessionWorkspace: URL?) -> Bool {
        guard let storeWorkspace, let sessionWorkspace else { return false }
        return storeWorkspace.resolvingSymlinksInPath().standardizedFileURL
            == sessionWorkspace.resolvingSymlinksInPath().standardizedFileURL
    }

    /// Appends a debug-session report with the outcome the service reported.
    func recordDebugSession(startedAt: Date, status: ReportRecord.Status) {
        addRecord(ReportRecord(
            kind: .debug,
            title: "Debug Session",
            date: startedAt,
            duration: Date().timeIntervalSince(startedAt),
            status: status
        ))
    }

    /// Tracks session boundaries for this workspace only: leaving `.inactive` starts a
    /// session, returning to it records a `.debug` report with the service's outcome.
    private func handleDebugSessionState(_ state: DebugService.SessionState) {
        let service = DebugService.shared
        guard Self.recordsDebugSession(storeWorkspace: workspaceURL, sessionWorkspace: service.workspace?.fileURL)
        else { return }
        if state == .inactive {
            guard let start = debugSessionStartDate else { return }
            debugSessionStartDate = nil
            recordDebugSession(startedAt: start, status: service.sessionReportStatus)
        } else if debugSessionStartDate == nil {
            debugSessionStartDate = Date()
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ReportRecord].self, from: data)
        else { return }
        records = Array(decoded.prefix(Self.maximumRecords))
    }

    private func persist() {
        guard let fileURL,
              let data = try? JSONEncoder().encode(records)
        else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
