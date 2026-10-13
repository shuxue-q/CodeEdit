//
//  WorkspaceDocument+NativeProjects.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

// MARK: - CMake and Flutter projects

extension WorkspaceDocument {
    /// Creates the CMake workspace and build controller, recording each finished build
    /// (with its diagnostics and log) in the workspace's report store.
    /// - Parameters:
    ///   - url: The workspace folder.
    ///   - sourceDirectory: The directory holding the `CMakeLists.txt`, when it is nested in the
    ///     workspace (a Flutter project's native root).
    ///   - reportStore: Records finished builds.
    func configureCMakeWorkspace(url: URL, sourceDirectory: URL? = nil, reportStore: ReportStore) {
        let sourceDirectory = sourceDirectory ?? url
        let cmakeWorkspace = CMakeWorkspace(sourceDirectory: sourceDirectory, workspaceDirectory: url)
        objectWillChange.send()
        self.cmakeWorkspace = cmakeWorkspace
        cmakeWorkspace.reload()
        let projectSettings = CMakeProjectSettingsStore(
            sourceDirectory: sourceDirectory,
            workspaceDirectory: url,
            workspace: cmakeWorkspace
        )
        self.cmakeProjectSettings = projectSettings
        let buildController = CMakeBuildController(
            sourceDirectory: sourceDirectory,
            workspace: cmakeWorkspace,
            projectSettings: projectSettings
        )
        buildController.onBuildFinished = { [weak self, weak buildController] success in
            guard let buildController else { return }
            self?.reportStore?.recordBuild(
                outcome: buildController.outcome,
                diagnostics: buildController.diagnostics,
                log: buildController.lastBuildLog,
                startedAt: buildController.lastBuildStartDate
            )
            // Failed builds surface their diagnostics; a build the user stopped does not.
            guard let self, !success, buildController.outcome != .cancelled else { return }
            if self.utilityAreaModel?.isCollapsed == true {
                CommandManager.shared.executeCommand("open.drawer")
            }
            self.utilityAreaModel?.selectedTab = .problems
        }
        self.cmakeBuildController = buildController
        taskManager?.cmakeBuildController = buildController
    }

    /// Stops and drops the CMake models, before closing or switching to another native root.
    func releaseCMakeWorkspace() {
        guard cmakeWorkspace != nil || cmakeProjectSettings != nil || cmakeBuildController != nil else { return }
        objectWillChange.send()
        cmakeWorkspace?.cancel()
        cmakeWorkspace = nil
        cmakeProjectSettings?.close()
        cmakeProjectSettings = nil
        cmakeBuildController?.stop()
        cmakeBuildController = nil
        taskManager?.cmakeBuildController = nil
    }

    /// Creates the Flutter model. Discovery runs in the background; when it settles on a native
    /// root other than the current CMake source directory, the CMake models are rebuilt for it
    /// and clangd is restarted with that root's compilation database.
    func configureFlutterWorkspace(url: URL) {
        let flutterWorkspace = FlutterWorkspace(workspaceDirectory: url)
        flutterWorkspace.onActiveNativeRootChange = { [weak self] nativeRoot in
            self?.applyNativeRoot(nativeRoot, workspaceURL: url)
        }
        self.flutterWorkspace = flutterWorkspace
        flutterWorkspace.reload()
    }

    private func applyNativeRoot(_ nativeRoot: URL?, workspaceURL url: URL) {
        guard let nativeRoot, let reportStore,
              nativeRoot.standardizedFileURL.path != cmakeWorkspace?.sourceDirectory.path else { return }
        let replacesRoot = cmakeWorkspace != nil
        releaseCMakeWorkspace()
        configureCMakeWorkspace(url: url, sourceDirectory: nativeRoot, reportStore: reportStore)
        guard replacesRoot else { return }
        // Running clangd servers were started with the previous root's database.
        NotificationCenter.default.post(
            name: CMakeWorkspace.configurePresetDidChangeNotification,
            object: cmakeWorkspace,
            userInfo: [CMakeWorkspace.sourceDirectoryUserInfoKey: url.standardizedFileURL.path]
        )
    }
}
