//
//  FlutterWorkspace.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation
import Observation

/// Workspace-owned Flutter discovery: the project, the Flutter SDK and the active native CMake
/// root. File reading and SDK lookup run off the main actor.
@MainActor
@Observable
final class FlutterWorkspace {
    /// The project, or `nil` before the first load or when the folder is not a Flutter project.
    private(set) var project: FlutterProject?
    /// The SDK of the `flutter` command on the login-shell `PATH`.
    private(set) var sdk: FlutterSDK?
    /// Whether the project is being read.
    private(set) var isLoading = false
    /// Whether the SDK is being located.
    private(set) var isLocatingSDK = false
    /// Whether the SDK lookup finished at least once.
    private(set) var hasLocatedSDK = false
    /// The native CMake root the CMake models and clangd use.
    private(set) var activeNativeRoot: URL?

    /// Called on the main actor when ``activeNativeRoot`` changes, including the first load.
    @ObservationIgnored var onActiveNativeRootChange: ((URL?) -> Void)?

    /// The workspace folder holding `pubspec.yaml`.
    let workspaceDirectory: URL

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var sdkTask: Task<Void, Never>?

    /// - Parameters:
    ///   - workspaceDirectory: The workspace folder.
    ///   - defaults: Where the native root choice is persisted.
    init(workspaceDirectory: URL, defaults: UserDefaults = .standard) {
        self.workspaceDirectory = workspaceDirectory.standardizedFileURL
        self.defaults = defaults
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

    /// Makes `nativeRoot` the active root and remembers the choice for this workspace.
    func selectNativeRoot(_ nativeRoot: URL) {
        let path = nativeRoot.standardizedFileURL.path
        guard let nativeRoot = nativeRoots.first(where: { $0.path == path }) else { return }
        FlutterProject.saveNativeRoot(nativeRoot, workspaceDirectory: workspaceDirectory, defaults: defaults)
        setActiveNativeRoot(nativeRoot)
    }

    /// Re-reads the project and native roots, and locates the SDK on the first call.
    func reload() {
        loadTask?.cancel()
        isLoading = true
        let directory = workspaceDirectory
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
        }
        if !hasLocatedSDK && sdkTask == nil {
            locateSDK()
        }
    }

    /// Looks up the Flutter SDK again, for example after the user installs it.
    func locateSDK() {
        sdkTask?.cancel()
        isLocatingSDK = true
        sdkTask = Task { [weak self] in
            let sdk = await Task.detached(priority: .utility) { FlutterSDK.locate() }.value
            guard !Task.isCancelled, let self else { return }
            self.sdk = sdk
            self.isLocatingSDK = false
            self.hasLocatedSDK = true
            self.sdkTask = nil
        }
    }

    /// Allows callers and tests to wait for the current discovery pass.
    func waitForReload() async { await loadTask?.value }

    /// Stops discovery and drops the change callback.
    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        sdkTask?.cancel()
        sdkTask = nil
        isLoading = false
        isLocatingSDK = false
        onActiveNativeRootChange = nil
    }

    private func setActiveNativeRoot(_ nativeRoot: URL?) {
        guard nativeRoot?.path != activeNativeRoot?.path else { return }
        activeNativeRoot = nativeRoot
        onActiveNativeRootChange?(nativeRoot)
    }
}
