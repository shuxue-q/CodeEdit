//
//  TaskDiagnosticsStore.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation
import Observation

/// Problems parsed from generated tasks' output, per task. Merged into the Problems panel, the
/// Issues navigator and the toolbar counts by ``WorkspaceDiagnostics``.
@MainActor
@Observable
final class TaskDiagnosticsStore {
    /// The most problems kept for one task run.
    static let maximumPerTask = 2_000

    private(set) var diagnosticsByTask: [UUID: [CMakeBuildDiagnostic]] = [:]
    /// Task names for display, keyed like ``diagnosticsByTask``.
    private(set) var taskNames: [UUID: String] = [:]

    /// Every task's problems, in task-run order.
    var all: [CMakeBuildDiagnostic] {
        diagnosticsByTask.keys.sorted { $0.uuidString < $1.uuidString }.flatMap { diagnosticsByTask[$0] ?? [] }
    }

    /// Whether no task reported a problem.
    var isEmpty: Bool { diagnosticsByTask.values.allSatisfy(\.isEmpty) }

    /// Forgets a task's problems when it starts again.
    func reset(taskID: UUID, name: String) {
        diagnosticsByTask[taskID] = []
        taskNames[taskID] = name
    }

    /// Adds problems found in a task's output, skipping exact repeats.
    func append(_ diagnostics: [CMakeBuildDiagnostic], taskID: UUID) {
        guard !diagnostics.isEmpty else { return }
        var current = diagnosticsByTask[taskID] ?? []
        for diagnostic in diagnostics where current.count < Self.maximumPerTask {
            let isRepeat = current.contains {
                $0.severity == diagnostic.severity && $0.message == diagnostic.message
                    && $0.filePath == diagnostic.filePath && $0.line == diagnostic.line
                    && $0.column == diagnostic.column
            }
            if !isRepeat { current.append(diagnostic) }
        }
        diagnosticsByTask[taskID] = current
    }

    /// Removes every task's problems (the Problems panel's Clear button).
    func clearAll() {
        diagnosticsByTask = [:]
    }
}

/// Watches one run of a generated task: splits its terminal output into lines, feeds the task's
/// parser, and notices `flutter run` becoming ready for hot reload and reporting reloads.
@MainActor
final class TaskOutputMonitor {
    /// Events a `flutter run` prints that matter to CodeEdit.
    enum FlutterRunEvent: Equatable {
        /// The app is running and accepts `r`/`R`.
        case readyForHotReload
        /// A reload or restart finished, with Flutter's summary line.
        case reloaded(String)
        /// A reload failed or was rejected, with Flutter's message.
        case reloadFailed(String)
    }

    private let taskID: UUID
    private weak var store: TaskDiagnosticsStore?
    private var parser: (any TaskOutputParser)?
    private let watchesFlutterRun: Bool
    private var pendingBytes: [UInt8] = []
    private var isFinished = false
    /// Called for each Flutter run event.
    var onFlutterRunEvent: ((FlutterRunEvent) -> Void)?

    /// - Parameters:
    ///   - taskID: The task whose output this is.
    ///   - name: The task name, for the store.
    ///   - parserKind: How to read problems from the output; `nil` reads none.
    ///   - baseDirectory: The task's working directory, for relative paths.
    ///   - store: Where problems go.
    ///   - watchesFlutterRun: Whether to look for hot reload markers.
    init(
        taskID: UUID,
        name: String,
        parserKind: TaskOutputParserKind?,
        baseDirectory: URL,
        store: TaskDiagnosticsStore?,
        watchesFlutterRun: Bool
    ) {
        self.taskID = taskID
        self.store = store
        self.parser = parserKind?.makeParser(baseDirectory: baseDirectory)
        self.watchesFlutterRun = watchesFlutterRun
        store?.reset(taskID: taskID, name: name)
    }

    /// Reads a chunk of terminal output.
    func consume(_ bytes: ArraySlice<UInt8>) {
        guard !isFinished else { return }
        pendingBytes.append(contentsOf: bytes)
        // Bound the buffer for output that never ends a line (progress bars).
        if pendingBytes.count > 64 * 1024 {
            pendingBytes.removeFirst(pendingBytes.count - 64 * 1024)
        }
        // A pseudo-terminal ends lines with "\r\n"; a lone "\r" (progress output) ends one too.
        while let newline = pendingBytes.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            var terminatorLength = 1
            if pendingBytes[newline] == 0x0D {
                guard newline + 1 < pendingBytes.count else { break }
                if pendingBytes[newline + 1] == 0x0A { terminatorLength = 2 }
            }
            let lineBytes = Array(pendingBytes[..<newline])
            pendingBytes.removeFirst(newline + terminatorLength)
            handle(line: Self.decode(lineBytes))
        }
    }

    /// Flushes the last line and any diagnostic still waiting, when the process ends. Later calls
    /// and later output are ignored.
    func finish() {
        guard !isFinished else { return }
        isFinished = true
        while pendingBytes.last == 0x0D { pendingBytes.removeLast() }
        if !pendingBytes.isEmpty {
            handle(line: Self.decode(pendingBytes))
            pendingBytes = []
        }
        if var parser {
            let remaining = parser.finish()
            self.parser = parser
            store?.append(remaining, taskID: taskID)
        }
    }

    /// Decodes a line as UTF-8, falling back to Latin-1 so a stray byte never drops the line.
    private static func decode(_ bytes: [UInt8]) -> String {
        String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .isoLatin1) ?? ""
    }

    private func handle(line rawLine: String) {
        let line = TaskOutputText.strippingANSI(rawLine)
        if var parser {
            let found = parser.consume(line: line)
            self.parser = parser
            store?.append(found, taskID: taskID)
        }
        if watchesFlutterRun, let event = Self.flutterRunEvent(in: line) {
            onFlutterRunEvent?(event)
        }
    }

    /// The Flutter run event a line announces, if any.
    static func flutterRunEvent(in line: String) -> FlutterRunEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("Flutter run key commands.") || trimmed.hasPrefix("To hot reload changes while running") {
            return .readyForHotReload
        }
        if trimmed.hasPrefix("Reloaded ") || trimmed.hasPrefix("Restarted application in") {
            return .reloaded(trimmed)
        }
        if trimmed.hasPrefix("Hot reload rejected") || trimmed.hasPrefix("Hot reload was rejected")
            || trimmed.hasPrefix("Try performing a hot restart instead") {
            return .reloadFailed(trimmed)
        }
        return nil
    }
}
