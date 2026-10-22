//
//  ProjectEditorState.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/30/26.
//

import Foundation
import Observation

/// A workspace's project editor state that outlives the editor tab: the selected section and
/// the text files being edited, so unsaved edits survive switching tabs.
@MainActor
@Observable
final class ProjectEditorState {
    /// A section of the project editor.
    enum Section: Hashable, Identifiable {
        /// The components, links and toolchains of a hybrid workspace.
        case overview
        case flutter
        case rust
        /// The CMake panes grouped under one segment, in workspaces with several toolchains.
        case cpp
        case cmake(CMakeProjectSettingsStore.Pane)
        case versionControl
        case projectFiles

        var id: String { title }

        var title: String {
            switch self {
            case .overview: String(localized: "Overview")
            case .flutter: "Flutter"
            case .rust: "Rust"
            case .cpp: "C++"
            case .cmake(let pane): pane.title
            case .versionControl: String(localized: "Version Control")
            case .projectFiles: String(localized: "Project Files")
            }
        }
    }

    /// The group heading CodeEdit's own settings files are listed under.
    static let codeEditGroup = "CodeEdit"
    /// The group heading of tool configuration files that are not tied to a toolchain.
    static let toolsGroup = "Tools"

    /// Configuration files listed in the Project Files section, relative to the workspace root.
    static let configurationFilePaths = [
        ".codeedit/settings.json",
        ".codeedit/\(CMakeProjectSettings.fileName)",
        ".clang-format",
        ".clang-tidy",
        ".clangd",
        ".editorconfig",
    ]

    let rootURL: URL
    /// `nil` until chosen; the editor then shows its first section.
    var selectedSection: Section?
    /// The CMake pane shown inside the grouped C++ section.
    var selectedCMakePane: CMakeProjectSettingsStore.Pane = .toolchain
    /// The Cargo root shown in the Rust section, by folder path; `nil` shows the first.
    var selectedCargoRoot: String?

    let gitignore: ProjectTextFile
    private(set) var configurationFiles: [ProjectTextFile]
    /// The heading each configuration file is listed under, keyed by file ID.
    private(set) var fileGroups: [ProjectTextFile.ID: String] = [:]
    var selectedConfigurationFile: ProjectTextFile.ID?

    private let includesCMakeSettings: Bool
    private let baseFiles: [ProjectTextFile]

    /// - Parameter includesCMakeSettings: Lists the CMake settings file, for CMake projects.
    /// - Parameter includesFlutterSettings: Lists the Flutter settings file, for Flutter projects.
    init(rootURL: URL, includesCMakeSettings: Bool, includesFlutterSettings: Bool = false) {
        self.rootURL = rootURL.standardizedFileURL
        self.includesCMakeSettings = includesCMakeSettings
        gitignore = ProjectTextFile(url: self.rootURL.appending(path: ".gitignore"), displayPath: ".gitignore")
        var paths = Self.configurationFilePaths
            .filter { includesCMakeSettings || !$0.hasSuffix(CMakeProjectSettings.fileName) }
        if includesFlutterSettings {
            paths.insert(".codeedit/\(FlutterProjectSettings.fileName)", at: 1)
        }
        let root = rootURL.standardizedFileURL
        baseFiles = paths.map { ProjectTextFile(url: root.appending(path: $0), displayPath: $0) }
        configurationFiles = baseFiles
        for file in baseFiles {
            fileGroups[file.id] = file.displayPath.hasPrefix(".codeedit/") ? Self.codeEditGroup : Self.toolsGroup
        }
        selectedConfigurationFile = configurationFiles.first?.id
    }

    /// Every text file the project editor edits.
    var allFiles: [ProjectTextFile] {
        [gitignore] + configurationFiles
    }

    /// The configuration files grouped for display: CodeEdit settings, then each toolchain's
    /// files, then other tool files.
    var groupedConfigurationFiles: [(group: String, files: [ProjectTextFile])] {
        var order = [Self.codeEditGroup] + ProjectToolchain.allCases.map(\.title) + [Self.toolsGroup]
        for group in fileGroups.values where !order.contains(group) { order.append(group) }
        return order.compactMap { group in
            let files = configurationFiles.filter { fileGroups[$0.id] == group }
            return files.isEmpty ? nil : (group, files)
        }
    }

    /// Adds the configuration files project discovery found, keeping the files (and their unsaved
    /// edits) that were already listed.
    /// - Parameters:
    ///   - discovered: Files from ``ProjectInventory/configurationFiles``.
    ///   - toolchains: The workspace's toolchains; Cargo adds its settings file.
    func updateDiscoveredFiles(_ discovered: [ProjectConfigurationFile], toolchains: [ProjectToolchain]) {
        var files = baseFiles
        var groups: [ProjectTextFile.ID: String] = [:]
        for file in baseFiles { groups[file.id] = fileGroups[file.id] }
        func add(_ relativePath: String, group: String) {
            let url = rootURL.appending(path: relativePath).standardizedFileURL
            guard !files.contains(where: { $0.url == url }) else { return }
            let file = configurationFiles.first { $0.url == url }
                ?? ProjectTextFile(url: url, displayPath: relativePath)
            files.append(file)
            groups[file.id] = group
        }
        if toolchains.contains(.cargo) {
            add(".codeedit/\(CargoProjectSettings.fileName)", group: Self.codeEditGroup)
        }
        for file in discovered {
            add(file.relativePath, group: file.toolchain.title)
        }
        // Keep CodeEdit's files first, in their original order.
        let codeEditFiles = files.filter { groups[$0.id] == Self.codeEditGroup }
        files = codeEditFiles + files.filter { groups[$0.id] != Self.codeEditGroup }
        configurationFiles = files
        fileGroups = groups
        if let selected = selectedConfigurationFile, !files.contains(where: { $0.id == selected }) {
            selectedConfigurationFile = files.first?.id
        }
    }

    /// Picks up changes made on disk to every file.
    func checkForExternalChanges() {
        allFiles.forEach { $0.checkForExternalChanges() }
    }
}
