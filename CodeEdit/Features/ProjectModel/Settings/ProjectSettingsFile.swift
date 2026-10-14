//
//  ProjectSettingsFile.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation
import Observation
import OSLog

/// A settings value stored as JSON in the workspace's `.codeedit` folder.
protocol ProjectSettingsValue: Codable, Equatable, Sendable {
    /// The file name inside `.codeedit`.
    static var fileName: String { get }
    /// The value used when the file is missing.
    init()
}

/// Loads and saves one `.codeedit/<name>.json` settings file.
///
/// Edits are saved half a second after they stop. A file that exists but cannot be decoded is
/// reported in ``loadError`` and replaced on the next save; decoding is lenient, so this only
/// happens for files that are not JSON objects.
@MainActor
@Observable
final class ProjectSettingsFile<Value: ProjectSettingsValue> {
    /// The current settings. Setting a different value schedules a save and calls ``onChange``.
    var value: Value {
        didSet {
            guard value != oldValue, !isReloading else { return }
            scheduleSave()
            onChange?(value)
        }
    }

    /// Why the file could not be read, when it exists but is unreadable.
    private(set) var loadError: String?
    /// Why the last save failed.
    private(set) var saveError: String?

    /// `<workspace>/.codeedit/<Value.fileName>`.
    let fileURL: URL

    /// Called after ``value`` changes, from an edit or a reload from disk.
    @ObservationIgnored var onChange: ((Value) -> Void)?

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var isReloading = false

    private static var logger: Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "ProjectSettingsFile")
    }

    /// Loads the settings of a workspace.
    /// - Parameter workspaceDirectory: The workspace folder holding `.codeedit`.
    init(workspaceDirectory: URL) {
        fileURL = Self.fileURL(for: workspaceDirectory)
        do {
            value = try Self.read(from: fileURL) ?? Value()
        } catch {
            value = Value()
            loadError = error.localizedDescription
        }
    }

    /// The settings file of a workspace.
    nonisolated static func fileURL(for workspaceDirectory: URL) -> URL {
        workspaceDirectory.standardizedFileURL
            .appending(path: ".codeedit", directoryHint: .isDirectory)
            .appending(path: Value.fileName)
    }

    /// Reads a workspace's saved settings without creating a store, for background work.
    nonisolated static func saved(in workspaceDirectory: URL) -> Value? {
        try? read(from: fileURL(for: workspaceDirectory))
    }

    /// Reads a settings file, returning `nil` when it does not exist.
    nonisolated static func read(from url: URL) throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }

    /// Writes the settings as pretty-printed JSON with sorted keys, creating `.codeedit/`.
    func save() throws {
        saveTask?.cancel()
        saveTask = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        loadError = nil
        saveError = nil
    }

    /// Re-reads the file after it was edited as text, dropping a pending save.
    func reloadFromDisk() {
        saveTask?.cancel()
        saveTask = nil
        do {
            let loaded = try Self.read(from: fileURL) ?? Value()
            loadError = nil
            guard loaded != value else { return }
            isReloading = true
            value = loaded
            isReloading = false
            onChange?(loaded)
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Saves a pending edit now, for example before the workspace closes.
    func flush() {
        guard saveTask != nil else { return }
        do {
            try save()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            do {
                try self.save()
            } catch {
                self.saveError = error.localizedDescription
                Self.logger.error("Failed to save \(Value.fileName): \(error.localizedDescription)")
            }
        }
    }
}
