//
//  WorkspaceDocument+ProjectInventory.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

// MARK: - Hybrid project discovery and generated tasks

extension WorkspaceDocument {
    /// Starts project discovery, keeps the generated tasks in step with the inventory and
    /// settings, rescans on configuration file changes, and hot-reloads on save.
    func configureProjectInventory(url: URL) {
        let model = ProjectInventoryModel(workspaceDirectory: url)
        projectInventory = model
        model.onInventoryChange = { [weak self] previous, inventory in
            self?.inventoryDidChange(from: previous, to: inventory)
        }
        model.cargoSettings.onChange = { [weak self] _ in self?.regenerateTasks() }
        flutterWorkspace?.onReload = { [weak self] in self?.regenerateTasks() }
        flutterWorkspace?.settings.onChange = { [weak self] _ in self?.regenerateTasks() }
        workspaceFileManager?.rawEventHandler = { [weak self] paths in
            self?.handleConfigurationFileEvents(paths)
        }

        let center = NotificationCenter.default
        projectObservers.append(center.addObserver(
            forName: CodeFileDocument.didSaveNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let url = notification.object as? URL else { return }
            MainActor.assumeIsolated { self?.documentDidSave(url) }
        })
        for name in [CMakeWorkspace.configurePresetDidChangeNotification,
                     CMakeProjectSettingsStore.configureInputsDidChangeNotification] {
            projectObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.regenerateTasks() }
            })
        }
        model.reload()
    }

    /// Stops discovery and removes the observers, when the workspace closes.
    func releaseProjectInventory() {
        projectObservers.forEach(NotificationCenter.default.removeObserver)
        projectObservers = []
        hotReloadOnSaveTask?.cancel()
        projectInventory?.cancel()
        projectInventory = nil
    }

    /// Rebuilds the generated tasks from the inventory, the Flutter and Cargo settings and the
    /// CMake models.
    func regenerateTasks() {
        guard let taskManager, let inventory = projectInventory?.inventory else { return }
        let flutterInputs = flutterWorkspace.map { flutter in
            ProjectTaskCatalog.FlutterInputs(
                settings: flutter.settings.value,
                sdkBinDirectory: flutter.sdkOverride == nil ? nil : flutter.sdk?.rootDirectory.appending(path: "bin"),
                device: flutter.selectedDevice
            )
        }
        var cmakeInputs: ProjectTaskCatalog.CMakeInputs?
        if cmakeBuildController != nil, let cmakeProjectSettings {
            let isMultiConfig = cmakeWorkspace?.configurePreset?.isMultiConfig == true
            cmakeInputs = ProjectTaskCatalog.CMakeInputs(
                projectName: cmakeWorkspace?.project?.name ?? "C++",
                buildDirectory: cmakeProjectSettings.configureOptions.buildDirectory,
                configuration: isMultiConfig ? cmakeWorkspace?.buildType : nil
            )
        }
        taskManager.setGeneratedTasks(ProjectTaskCatalog.tasks(
            inventory: inventory,
            flutter: flutterInputs,
            cargoSettings: projectInventory?.cargoSettings.value ?? CargoProjectSettings(),
            cmake: cmakeInputs
        ))
    }

    private func inventoryDidChange(from previous: ProjectInventory?, to inventory: ProjectInventory) {
        regenerateTasks()
        projectEditorState?.updateDiscoveredFiles(inventory.configurationFiles, toolchains: inventory.toolchains)
        // rust-analyzer reads its linked projects when it starts; restart it when they change.
        if let previous, previous.cargoRoots.map(\.directory) != inventory.cargoRoots.map(\.directory),
           let path = fileURL?.path(percentEncoded: false),
           let lspService = ServiceContainer.resolve(.singleton, LSPService.self) {
            lspService.restartServers(languageIds: ["rust"], workspacePath: path)
        }
    }

    /// Rescans when a configuration file changed on disk, whoever changed it.
    private func handleConfigurationFileEvents(_ paths: [String]) {
        projectInventory?.handleFileEvents(paths: paths)
        guard let flutterWorkspace else { return }
        // File system events report resolved paths (`/private/var/…` for `/var/…`).
        let root = flutterWorkspace.workspaceDirectory.resolvingSymlinksInPath().path
        let flutterFiles: Set<String> = [
            PubspecParser.fileName, "pubspec.lock", AnalysisOptions.fileName, FlutterMetadata.fileName,
            "package_config.json", "build.dart", "ffigen.yaml", FlutterProjectSettings.fileName
        ]
        let subfolders: Set<String> = ["hook", ".dart_tool", ".codeedit"]
        let touchesFlutter = paths.contains { path in
            let name = (path as NSString).lastPathComponent
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path as NSString
            let parent = (resolved.deletingLastPathComponent as NSString)
            guard flutterFiles.contains(name) else { return false }
            return parent as String == root
                || parent.deletingLastPathComponent == root && subfolders.contains(parent.lastPathComponent)
        }
        if touchesFlutter {
            flutterWorkspace.reload()
        }
    }

    /// Hot-reloads a running Flutter app shortly after a Dart file in the workspace is saved.
    private func documentDidSave(_ url: URL) {
        guard url.pathExtension == "dart",
              let flutterWorkspace, flutterWorkspace.settings.value.hotReloadOnSave,
              let root = fileURL?.standardizedFileURL.path,
              url.standardizedFileURL.path.hasPrefix(root),
              taskManager?.canHotReload == true else { return }
        hotReloadOnSaveTask?.cancel()
        hotReloadOnSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.taskManager?.hotReload()
        }
    }
}
