//
//  CMakeWorkspace.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/11/26.
//

import Foundation
import Observation

/// Workspace-owned CMake discovery and local preset selection. File parsing runs off the main actor.
@MainActor
@Observable
final class CMakeWorkspace {
    /// Posted when the selected configure preset changes. The userInfo dictionary carries the
    /// workspace's source directory path under ``sourceDirectoryUserInfoKey``.
    static let configurePresetDidChangeNotification = Notification.Name("CMakeWorkspace.configurePresetDidChange")

    /// The userInfo key holding the workspace's source directory path.
    static let sourceDirectoryUserInfoKey = "sourceDirectory"

    private(set) var project: CMakeProject?
    private(set) var isLoading = false
    private(set) var selectedConfigurePreset = ""
    private(set) var selectedBuildPreset = ""

    private let sourceDirectory: URL
    private let defaults: UserDefaults
    private let selectionKey: String
    private var loadTask: Task<Void, Never>?

    init(sourceDirectory: URL, defaults: UserDefaults = .standard) {
        self.sourceDirectory = sourceDirectory.standardizedFileURL
        self.defaults = defaults
        selectionKey = Self.selectionKey(for: sourceDirectory)
        let saved = Self.savedSelection(sourceDirectory: sourceDirectory, defaults: defaults)
        selectedConfigurePreset = saved.configure
        selectedBuildPreset = saved.build
    }

    /// The defaults key the preset selection is persisted under.
    nonisolated static func selectionKey(for sourceDirectory: URL) -> String {
        "cmakeSelection-\(sourceDirectory.standardizedFileURL.path)"
    }

    /// Reads the persisted preset selection for a source directory without creating a workspace model.
    ///
    /// Useful for background work (for example compilation database generation) that must not hop
    /// onto the main actor to consult a ``CMakeWorkspace`` instance.
    /// - Parameters:
    ///   - sourceDirectory: The workspace's source directory.
    ///   - defaults: The defaults store the selection was saved to.
    /// - Returns: The selected configure and build preset names, empty when nothing was selected.
    nonisolated static func savedSelection(
        sourceDirectory: URL,
        defaults: UserDefaults = .standard
    ) -> (configure: String, build: String) {
        let saved = defaults.stringArray(forKey: selectionKey(for: sourceDirectory)) ?? []
        return (saved.first ?? "", saved.dropFirst().first ?? "")
    }

    var configurePreset: CMakePreset? {
        project?.configurePresets.first { $0.name == selectedConfigurePreset }
    }

    var availableBuildPresets: [CMakePreset] {
        project?.buildPresets.filter { $0.configurePreset == selectedConfigurePreset } ?? []
    }

    var buildPreset: CMakePreset? {
        availableBuildPresets.first { $0.name == selectedBuildPreset }
    }

    var buildType: String? {
        configurePreset?.isMultiConfig == true ? buildPreset?.configuration : configurePreset?.buildType
    }

    func selectConfigurePreset(_ name: String) {
        guard project?.configurePresets.contains(where: { $0.name == name }) == true else { return }
        selectedConfigurePreset = name
        validateSelection()
        saveSelection()
        NotificationCenter.default.post(
            name: Self.configurePresetDidChangeNotification,
            object: self,
            userInfo: [Self.sourceDirectoryUserInfoKey: sourceDirectory.path]
        )
    }

    func selectBuildPreset(_ name: String) {
        guard availableBuildPresets.contains(where: { $0.name == name }) else { return }
        selectedBuildPreset = name
        saveSelection()
    }

    func reload() {
        loadTask?.cancel()
        isLoading = true
        let directory = sourceDirectory
        loadTask = Task { [weak self] in
            let project = await Task.detached(priority: .userInitiated) {
                CMakeProject.load(at: directory)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.project = project
            self.validateSelection()
            self.isLoading = false
        }
    }

    /// Allows callers and tests to wait for the current discovery pass.
    func waitForReload() async { await loadTask?.value }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    private func validateSelection() {
        if configurePreset == nil { selectedConfigurePreset = project?.configurePresets.first?.name ?? "" }
        if buildPreset == nil { selectedBuildPreset = availableBuildPresets.first?.name ?? "" }
    }

    private func saveSelection() {
        defaults.set([selectedConfigurePreset, selectedBuildPreset], forKey: selectionKey)
    }
}
