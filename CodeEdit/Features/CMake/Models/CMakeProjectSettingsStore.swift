//
//  CMakeProjectSettingsStore.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/30/26.
//

import Foundation
import Observation
import OSLog

/// Owns a workspace's ``CMakeProjectSettings``: loads and saves `.codeedit/cmake-settings.json`,
/// and caches the toolchain scan and executable targets shown by the project editor.
///
/// Edits are saved shortly after they stop. When settings that affect configuration change,
/// ``configureInputsDidChangeNotification`` is posted so clangd picks up the new compile flags.
@MainActor
@Observable
final class CMakeProjectSettingsStore {
    /// Posted after saved settings change the configure step. The userInfo dictionary carries
    /// the workspace's source directory path under ``CMakeWorkspace/sourceDirectoryUserInfoKey``.
    static let configureInputsDidChangeNotification = Notification.Name(
        "CMakeProjectSettingsStore.configureInputsDidChange"
    )

    /// A CMake section of the project editor.
    enum Pane: String, CaseIterable, Identifiable {
        case toolchain = "Toolchain"
        case build = "Build Settings"
        case variables = "CMake Variables"
        case run = "Run / Debug"

        var id: String { rawValue }
    }

    var settings: CMakeProjectSettings {
        didSet {
            guard settings != oldValue, !isReloading else { return }
            scheduleSave()
        }
    }

    /// Why the settings file could not be read, if it exists but is unreadable. Saving
    /// replaces it.
    private(set) var loadError: String?
    private(set) var saveError: String?

    private(set) var toolchain: CMakeToolchainScan?
    private(set) var isScanningToolchain = false

    private(set) var executableTargets: [CMakeExecutableTarget] = []

    let sourceDirectory: URL
    let fileURL: URL

    /// Supplies the selected presets; weak because the workspace document owns both models.
    private weak var workspace: CMakeWorkspace?
    private var saveTask: Task<Void, Never>?
    private var notifyTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var targetsTask: Task<Void, Never>?
    private var hasUnsavedChanges = false
    /// Set while ``reloadFromDisk()`` replaces the settings, so the reload is not saved back.
    private var isReloading = false
    private var lastNotifiedInputs: ConfigureInputs

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "",
        category: "CMakeProjectSettingsStore"
    )

    /// The part of the settings that affects configure; changes to run settings alone do not
    /// restart clangd.
    private struct ConfigureInputs: Equatable {
        let toolchain: CMakeProjectSettings.Toolchain
        let build: CMakeProjectSettings.Build
        let definitions: [String]

        init(_ settings: CMakeProjectSettings) {
            toolchain = settings.toolchain
            build = settings.build
            definitions = settings.variables.compactMap(CMakeConfigureOptions.definition)
        }
    }

    init(sourceDirectory: URL, workspace: CMakeWorkspace?) {
        self.sourceDirectory = sourceDirectory.standardizedFileURL
        self.workspace = workspace
        fileURL = Self.fileURL(for: sourceDirectory)
        var loaded = CMakeProjectSettings()
        do {
            loaded = try Self.read(from: fileURL) ?? CMakeProjectSettings()
        } catch {
            loadError = error.localizedDescription
        }
        settings = loaded
        lastNotifiedInputs = ConfigureInputs(loaded)
    }

    // MARK: - Persistence

    /// The settings file for a workspace.
    nonisolated static func fileURL(for sourceDirectory: URL) -> URL {
        sourceDirectory.standardizedFileURL
            .appending(path: ".codeedit", directoryHint: .isDirectory)
            .appending(path: CMakeProjectSettings.fileName)
    }

    /// Reads the saved settings of a workspace without creating a store, for background work
    /// such as compilation database generation.
    /// - Returns: The saved settings, or `nil` when the workspace has no readable settings file.
    nonisolated static func savedSettings(sourceDirectory: URL) -> CMakeProjectSettings? {
        try? read(from: fileURL(for: sourceDirectory))
    }

    /// Reads a settings file, returning `nil` when it does not exist.
    nonisolated static func read(from url: URL) throws -> CMakeProjectSettings? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CMakeProjectSettings.self, from: data)
    }

    /// Writes the settings as pretty-printed JSON with sorted keys, creating `.codeedit/`.
    func save() throws {
        saveTask?.cancel()
        saveTask = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(settings)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        hasUnsavedChanges = false
        loadError = nil
        saveError = nil
        notifyIfConfigureInputsChanged()
    }

    /// Re-reads the settings file after it was edited as text. An unreadable file sets
    /// ``loadError`` and keeps the current settings.
    func reloadFromDisk() {
        saveTask?.cancel()
        saveTask = nil
        do {
            let loaded = try Self.read(from: fileURL) ?? CMakeProjectSettings()
            isReloading = true
            settings = loaded
            isReloading = false
            hasUnsavedChanges = false
            loadError = nil
            notifyIfConfigureInputsChanged()
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Saves pending edits immediately. Call before the workspace closes.
    func flush() {
        guard hasUnsavedChanges else { return }
        do {
            try save()
        } catch {
            Self.logger.error("Failed to save CMake settings: \(error.localizedDescription)")
        }
    }

    /// Cancels background work. Pending edits are saved first.
    func close() {
        flush()
        notifyTask?.cancel()
        scanTask?.cancel()
        targetsTask?.cancel()
    }

    private func scheduleSave() {
        hasUnsavedChanges = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            do {
                try self.save()
            } catch {
                self.saveError = error.localizedDescription
            }
        }
    }

    /// Tells clangd to regenerate its compilation database once configure inputs settle, so
    /// typing a variable name does not reconfigure the project on every keystroke.
    private func notifyIfConfigureInputsChanged() {
        let inputs = ConfigureInputs(settings)
        guard inputs != lastNotifiedInputs else { return }
        notifyTask?.cancel()
        notifyTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.lastNotifiedInputs = inputs
            NotificationCenter.default.post(
                name: Self.configureInputsDidChangeNotification,
                object: self,
                userInfo: [CMakeWorkspace.sourceDirectoryUserInfoKey: self.sourceDirectory.path]
            )
        }
    }

    // MARK: - Derived configuration

    /// The configure preset that overrides the toolchain and build settings, if one is selected.
    var activeConfigurePreset: CMakePreset? {
        workspace?.configurePreset
    }

    /// The invocation a build would use right now.
    var configureOptions: CMakeConfigureOptions {
        CMakeConfigureOptions(
            sourceDirectory: sourceDirectory,
            configurePreset: workspace?.configurePreset,
            buildPreset: workspace?.buildPreset,
            settings: settings
        )
    }

    /// The configuration whose artifacts are launched: the preset's build type when a preset is
    /// active, otherwise the configuration chosen in the settings.
    var effectiveConfiguration: String? {
        if workspace?.configurePreset != nil { return workspace?.buildType }
        return settings.build.configuration.rawValue
    }

    // MARK: - Toolchain

    /// Scans for compilers, CMake, and generator tools in the background. A scan in progress
    /// is reused unless `force` is set.
    func scanToolchain(force: Bool = false) {
        guard force || (toolchain == nil && !isScanningToolchain) else { return }
        scanTask?.cancel()
        isScanningToolchain = true
        scanTask = Task { [weak self] in
            let scan = await Task.detached(priority: .userInitiated) {
                CMakeToolchainDetector.scan(environment: LanguageServerDetector.userShellEnvironment())
            }.value
            guard !Task.isCancelled, let self else { return }
            self.toolchain = scan
            self.isScanningToolchain = false
        }
    }

    // MARK: - Executable targets

    /// Reloads the executable targets from the File API reply (or the list files) in the
    /// background.
    func refreshExecutableTargets() {
        targetsTask?.cancel()
        targetsTask = Task { [weak self] in
            guard let self else { return }
            let targets = await self.loadExecutableTargets()
            guard !Task.isCancelled else { return }
            self.executableTargets = targets
        }
    }

    /// Resolves what the debugger should launch, reading the latest targets first.
    /// - Returns: `nil` when no run target is chosen or its binary location is unknown.
    func resolveLaunchConfiguration() async -> CMakeLaunchConfiguration? {
        guard settings.run.hasExecutable else { return nil }
        executableTargets = await loadExecutableTargets()
        return settings.run.launchConfiguration(sourceDirectory: sourceDirectory, targets: executableTargets)
    }

    private func loadExecutableTargets() async -> [CMakeExecutableTarget] {
        let source = sourceDirectory
        let buildDirectory = configureOptions.buildDirectory
        let configuration = effectiveConfiguration
        return await Task.detached(priority: .userInitiated) {
            CMakeExecutableTargets.load(
                sourceDirectory: source,
                buildDirectory: buildDirectory,
                configuration: configuration
            )
        }.value
    }
}
