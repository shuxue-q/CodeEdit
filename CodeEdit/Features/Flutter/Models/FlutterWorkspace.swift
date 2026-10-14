//
//  FlutterWorkspace.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation
import Observation

/// Workspace-owned Flutter state: the project, the Flutter SDK, the active native CMake root,
/// the project's run settings and the devices `flutter run` can target. File reading, SDK lookup
/// and device listing run off the main actor.
@MainActor
@Observable
final class FlutterWorkspace {
    /// The project, or `nil` before the first load or when the folder is not a Flutter project.
    private(set) var project: FlutterProject?
    /// The SDK of the `flutter` command on the login-shell `PATH`, or of the override folder.
    private(set) var sdk: FlutterSDK?
    /// Whether the project is being read.
    private(set) var isLoading = false
    /// Whether the SDK is being located.
    private(set) var isLocatingSDK = false
    /// Whether the SDK lookup finished at least once.
    private(set) var hasLocatedSDK = false
    /// The native CMake root the CMake models and clangd use.
    private(set) var activeNativeRoot: URL?
    /// Devices from the last `flutter devices` listing; empty until listed.
    private(set) var devices: [FlutterDevice] = []
    /// Whether devices are being listed.
    private(set) var isListingDevices = false
    /// Whether devices were listed at least once.
    private(set) var hasListedDevices = false

    /// The project's Flutter settings, `.codeedit/flutter-settings.json`.
    let settings: ProjectSettingsFile<FlutterProjectSettings>

    /// Called on the main actor when ``activeNativeRoot`` changes, including the first load.
    @ObservationIgnored var onActiveNativeRootChange: ((URL?) -> Void)?
    /// Called on the main actor after the project or SDK is reloaded.
    @ObservationIgnored var onReload: (() -> Void)?

    /// The workspace folder holding `pubspec.yaml`.
    let workspaceDirectory: URL

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var sdkTask: Task<Void, Never>?
    @ObservationIgnored private var devicesTask: Task<Void, Never>?

    /// - Parameters:
    ///   - workspaceDirectory: The workspace folder.
    ///   - defaults: Where machine-specific choices (the SDK override) are persisted.
    init(workspaceDirectory: URL, defaults: UserDefaults = .standard) {
        self.workspaceDirectory = workspaceDirectory.standardizedFileURL
        self.defaults = defaults
        settings = ProjectSettingsFile(workspaceDirectory: workspaceDirectory)
    }

    /// Native roots found in the workspace, in discovery order.
    var nativeRoots: [URL] { project?.nativeRoots ?? [] }

    /// A root's path for display, `"."` for the workspace folder.
    func relativePath(of nativeRoot: URL) -> String {
        FlutterProject.relativePath(of: nativeRoot, in: workspaceDirectory)
    }

    /// A root's name for display: "Workspace Root", or its relative path with a trailing slash.
    func displayName(of nativeRoot: URL) -> String {
        let path = relativePath(of: nativeRoot)
        return path == "." ? "Workspace Root" : path + "/"
    }

    /// Makes `nativeRoot` the active root and saves the choice in the project settings right away,
    /// so background lookups such as the compilation database read the new root.
    func selectNativeRoot(_ nativeRoot: URL) {
        let path = nativeRoot.standardizedFileURL.path
        guard let nativeRoot = nativeRoots.first(where: { $0.path == path }) else { return }
        FlutterProject.saveNativeRoot(nativeRoot, workspaceDirectory: workspaceDirectory, defaults: defaults)
        settings.value.nativeRoot = relativePath(of: nativeRoot)
        try? settings.save()
        setActiveNativeRoot(nativeRoot)
    }

    // MARK: - Devices

    /// The device run tasks target: the chosen one, else macOS.
    var selectedDevice: FlutterDevice {
        let id = settings.value.device ?? FlutterDevice.macOS.id
        return devices.first { $0.id == id } ?? (id == FlutterDevice.macOS.id
            ? .macOS
            : FlutterDevice(id: id, name: id))
    }

    /// Lists connected devices with `flutter devices --machine`. It can take several seconds.
    func refreshDevices() {
        guard let flutter = flutterExecutablePath else {
            hasListedDevices = true
            return
        }
        devicesTask?.cancel()
        isListingDevices = true
        let directory = workspaceDirectory
        devicesTask = Task { [weak self] in
            let devices = await Task.detached(priority: .utility) {
                let environment = LanguageServerDetector.userShellEnvironment()
                let result = ToolProcess.run(
                    flutter,
                    ["devices", "--machine"],
                    in: directory,
                    environment: environment,
                    timeout: 60
                )
                return FlutterDevice.parse(machineOutput: result?.output ?? "")
            }.value
            guard !Task.isCancelled, let self else { return }
            self.devices = devices.filter(\.isSupported)
            self.isListingDevices = false
            self.hasListedDevices = true
        }
    }

    // MARK: - SDK override

    /// The defaults key of the per-workspace SDK override.
    nonisolated static func sdkOverrideKey(for workspaceDirectory: URL) -> String {
        "flutterSDKOverride-\(workspaceDirectory.standardizedFileURL.path)"
    }

    /// The SDK folder chosen for this workspace instead of the one on `PATH`, if any.
    var sdkOverride: String? {
        defaults.string(forKey: Self.sdkOverrideKey(for: workspaceDirectory))
    }

    /// The SDK override of a workspace, for background work such as starting the Dart server.
    nonisolated static func sdkOverride(for workspaceDirectory: URL, defaults: UserDefaults = .standard) -> URL? {
        guard let path = defaults.string(forKey: sdkOverrideKey(for: workspaceDirectory))?.trimmedNonEmpty else {
            return nil
        }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    /// Sets or clears (`nil` or empty) the SDK override and locates the SDK again.
    func setSDKOverride(_ path: String?) {
        if let path = path?.trimmedNonEmpty {
            defaults.set(path, forKey: Self.sdkOverrideKey(for: workspaceDirectory))
        } else {
            defaults.removeObject(forKey: Self.sdkOverrideKey(for: workspaceDirectory))
        }
        locateSDK()
    }

    /// The `flutter` executable tasks run: the override SDK's, else the located SDK's.
    var flutterExecutablePath: String? {
        sdk.map { $0.rootDirectory.appending(path: "bin/flutter").path }
    }

    // MARK: - Loading

    /// Re-reads the project and native roots, and locates the SDK on the first call.
    func reload() {
        loadTask?.cancel()
        isLoading = true
        let directory = workspaceDirectory
        settings.reloadFromDisk()
        loadTask = Task { [weak self] in
            let project = await Task.detached(priority: .userInitiated) {
                FlutterProject.load(at: directory)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.project = project
            self.isLoading = false
            let saved = FlutterProject.savedNativeRoot(workspaceDirectory: directory, defaults: self.defaults)
            self.setActiveNativeRoot(FlutterProject.activeNativeRoot(
                among: project?.nativeRoots ?? [],
                workspaceDirectory: directory,
                saved: saved
            ))
            self.onReload?()
        }
        if !hasLocatedSDK && sdkTask == nil {
            locateSDK()
        }
    }

    /// Looks up the Flutter SDK again, for example after the user installs it.
    func locateSDK() {
        sdkTask?.cancel()
        isLocatingSDK = true
        let override = Self.sdkOverride(for: workspaceDirectory, defaults: defaults)
        sdkTask = Task { [weak self] in
            let sdk = await Task.detached(priority: .utility) {
                if let override {
                    return FlutterSDK.sdk(forExecutable: override.appending(path: "bin/flutter"))
                }
                return FlutterSDK.locate()
            }.value
            guard !Task.isCancelled, let self else { return }
            self.sdk = sdk
            self.isLocatingSDK = false
            self.hasLocatedSDK = true
            self.sdkTask = nil
            self.onReload?()
        }
    }

    /// Allows callers and tests to wait for the current discovery pass.
    func waitForReload() async { await loadTask?.value }

    /// Stops discovery and drops the change callbacks.
    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        sdkTask?.cancel()
        sdkTask = nil
        devicesTask?.cancel()
        devicesTask = nil
        isLoading = false
        isLocatingSDK = false
        isListingDevices = false
        onActiveNativeRootChange = nil
        onReload = nil
        settings.flush()
    }

    private func setActiveNativeRoot(_ nativeRoot: URL?) {
        guard nativeRoot?.path != activeNativeRoot?.path else { return }
        activeNativeRoot = nativeRoot
        onActiveNativeRootChange?(nativeRoot)
    }
}
