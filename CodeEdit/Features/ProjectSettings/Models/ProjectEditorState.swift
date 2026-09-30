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
        case cmake(CMakeProjectSettingsStore.Pane)
        case versionControl
        case projectFiles

        var id: String { title }

        var title: String {
            switch self {
            case .cmake(let pane): pane.rawValue
            case .versionControl: "Version Control"
            case .projectFiles: "Project Files"
            }
        }
    }

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

    let gitignore: ProjectTextFile
    let configurationFiles: [ProjectTextFile]
    var selectedConfigurationFile: ProjectTextFile.ID?

    /// - Parameter includesCMakeSettings: Lists the CMake settings file, for CMake projects.
    init(rootURL: URL, includesCMakeSettings: Bool) {
        self.rootURL = rootURL.standardizedFileURL
        gitignore = ProjectTextFile(url: self.rootURL.appending(path: ".gitignore"), displayPath: ".gitignore")
        configurationFiles = Self.configurationFilePaths
            .filter { includesCMakeSettings || !$0.hasSuffix(CMakeProjectSettings.fileName) }
            .map { ProjectTextFile(url: rootURL.standardizedFileURL.appending(path: $0), displayPath: $0) }
        selectedConfigurationFile = configurationFiles.first?.id
    }

    /// Every text file the project editor edits.
    var allFiles: [ProjectTextFile] {
        [gitignore] + configurationFiles
    }

    /// Picks up changes made on disk to every file.
    func checkForExternalChanges() {
        allFiles.forEach { $0.checkForExternalChanges() }
    }
}
