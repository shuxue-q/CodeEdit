//
//  ProjectInventoryModel.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation
import Observation

/// Workspace-owned project discovery for hybrid workspaces: the ``ProjectInventory``, the Cargo
/// settings, and the toolchain probes. Scans and probes run off the main actor; configuration
/// file changes trigger a debounced rescan.
@MainActor
@Observable
final class ProjectInventoryModel {
    /// The latest scan, `nil` until the first scan finishes.
    private(set) var inventory: ProjectInventory?
    private(set) var isScanning = false
    /// Tool versions, `nil` until probed.
    private(set) var toolchainStatus: ToolchainStatus?
    private(set) var isProbing = false

    /// The project's Cargo settings, `.codeedit/cargo-settings.json`.
    let cargoSettings: ProjectSettingsFile<CargoProjectSettings>
    /// The workspace folder.
    let workspaceDirectory: URL

    /// Called on the main actor after each scan with the previous and the new inventory.
    @ObservationIgnored var onInventoryChange: ((ProjectInventory?, ProjectInventory) -> Void)?

    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var probeTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?

    /// - Parameter workspaceDirectory: The workspace folder.
    init(workspaceDirectory: URL) {
        self.workspaceDirectory = workspaceDirectory.standardizedFileURL
        cargoSettings = ProjectSettingsFile(workspaceDirectory: workspaceDirectory)
    }

    /// Scans the workspace again. Probes toolchains after the first scan.
    func reload() {
        scanTask?.cancel()
        isScanning = true
        let directory = workspaceDirectory
        scanTask = Task { [weak self] in
            let inventory = await Task.detached(priority: .userInitiated) {
                ProjectInventory.scan(workspace: directory)
            }.value
            guard !Task.isCancelled, let self else { return }
            let previous = self.inventory
            self.inventory = inventory
            self.isScanning = false
            self.onInventoryChange?(previous, inventory)
            let rootsChanged = previous?.cargoRoots.map(\.directory) != inventory.cargoRoots.map(\.directory)
            if self.toolchainStatus == nil || rootsChanged || previous?.toolchains != inventory.toolchains {
                self.probeToolchains()
            }
        }
    }

    /// Waits for the current scan, for tests.
    func waitForReload() async { await scanTask?.value }

    /// Asks the installed tools for their versions again.
    func probeToolchains() {
        guard let inventory else { return }
        probeTask?.cancel()
        isProbing = true
        let roots = inventory.cargoRoots.map(\.directory)
        let includeCMake = inventory.toolchains.contains(.cmake)
        probeTask = Task { [weak self] in
            let status = await Task.detached(priority: .utility) {
                ToolchainProbe.probe(cargoRoots: roots, includeCMake: includeCMake)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.toolchainStatus = status
            self.isProbing = false
        }
    }

    /// The Rust status of a Cargo root, once probed.
    func rustStatus(for root: CargoRoot) -> RustToolchainStatus? {
        toolchainStatus?.rust[root.directory.path]
    }

    // MARK: - File changes

    /// Reacts to file system events: rescans when a configuration file changed.
    /// - Parameter paths: Absolute paths reported by the file system event stream.
    func handleFileEvents(paths: [String]) {
        guard paths.contains(where: Self.isRelevant) else { return }
        if paths.contains(where: { $0.hasSuffix("/.codeedit/\(CargoProjectSettings.fileName)") }) {
            cargoSettings.reloadFromDisk()
        }
        scheduleReload()
    }

    /// Rescans shortly, coalescing bursts of changes (Save All, `pub get`).
    func scheduleReload() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    /// Whether a changed path is a configuration file worth a rescan.
    nonisolated static func isRelevant(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        if path.hasSuffix("/.codeedit/\(CargoProjectSettings.fileName)") { return true }
        guard ProjectInventory.watchedFileNames.contains(name) else { return false }
        if name == "package_config.json" { return path.hasSuffix("/.dart_tool/package_config.json") }
        if name == "config.toml" { return path.hasSuffix("/.cargo/config.toml") }
        let ignored = ["/build/", "/target/", "/.dart_tool/", "/.git/", "/node_modules/", "/ephemeral/"]
        return !ignored.contains { path.contains($0) }
    }

    /// Stops scans and probes and saves pending settings.
    func cancel() {
        scanTask?.cancel()
        probeTask?.cancel()
        debounceTask?.cancel()
        onInventoryChange = nil
        cargoSettings.flush()
    }
}
