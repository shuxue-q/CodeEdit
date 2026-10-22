//
//  ProjectInventory+Components.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

/// Finding Flutter and Dart packages, CMake projects and Cargo roots.
extension ProjectInventory {
    // MARK: Flutter and Dart

    mutating func addDartPackages(_ folders: [URL]) {
        for folder in folders {
            guard let pubspec = PubspecParser.read(in: folder) else { continue }
            let isRoot = folder == workspaceDirectory
            let kind: ProjectComponent.Kind
            let isFlutter = pubspec.dependsOnFlutter || !pubspec.ffiPluginPlatforms.isEmpty
            if !pubspec.pluginPlatforms.isEmpty {
                kind = .flutterPlugin
            } else if isFlutter {
                let metadata = FlutterMetadata.read(in: folder)
                kind = metadata?.projectType == "app" || (metadata == nil && isRoot) ? .flutterApp : .flutterPackage
            } else {
                kind = .dartPackage
            }
            var role = role(for: folder)
            if role == .primary && !isRoot { role = .member }
            components.append(ProjectComponent(
                kind: kind,
                role: role,
                name: pubspec.name ?? folder.lastPathComponent,
                detail: pubspec.version,
                directory: folder,
                relativePath: relativePath(of: folder)
            ))
        }
    }

    // MARK: CMake

    mutating func addCMakeProjects(_ folders: [URL]) {
        var runnerFolders: [URL] = []
        let flutterFolders = components.filter { $0.kind.toolchain == .flutter }.map(\.directory)
        for folder in folders {
            let parent = folder.deletingLastPathComponent().standardizedFileURL
            let isRunner = ["linux", "windows"].contains(folder.lastPathComponent)
                && flutterFolders.contains(parent)
                && FileManager.default.fileExists(atPath: folder.appending(path: "flutter/CMakeLists.txt").path)
            if isRunner {
                runnerFolders.append(folder)
                components.append(component(forCMake: folder, kind: .platformRunner, role: .generated))
                continue
            }
            if runnerFolders.contains(where: { folder.path.hasPrefix($0.path + "/") }) { continue }
            let isRoot = folder == workspaceDirectory
            // Below the root, only folders that start a project of their own count; the rest are
            // `add_subdirectory` folders of a parent project.
            guard isRoot || Self.declaresProject(folder) else { continue }
            var role = role(for: folder)
            if role == .primary && !isRoot && CMakeProject.isCMakeProject(at: workspaceDirectory) {
                role = .member
            }
            components.append(component(forCMake: folder, kind: .cmakeProject, role: role))
        }
    }

    func component(
        forCMake folder: URL,
        kind: ProjectComponent.Kind,
        role: ProjectComponent.Role
    ) -> ProjectComponent {
        let text = (try? String(contentsOf: folder.appending(path: "CMakeLists.txt"), encoding: .utf8)) ?? ""
        let metadata = try? CMakeListParser.parse(text)
        return ProjectComponent(
            kind: kind,
            role: role,
            name: metadata?.name ?? folder.lastPathComponent,
            detail: metadata?.version,
            directory: folder,
            relativePath: relativePath(of: folder)
        )
    }

    /// Whether the folder's `CMakeLists.txt` calls `project()`.
    static func declaresProject(_ folder: URL) -> Bool {
        guard let text = try? String(contentsOf: folder.appending(path: "CMakeLists.txt"), encoding: .utf8) else {
            return false
        }
        return text.split(whereSeparator: \.isNewline).contains { line in
            line.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("project(")
        }
    }

    // MARK: Cargo

    mutating func addCargoRoots() {
        for manifest in CargoProject.rootManifests(in: workspaceDirectory) {
            guard let root = CargoRoot.load(manifest: manifest, within: workspaceDirectory) else { continue }
            let role = role(for: root.directory)
            components.append(ProjectComponent(
                kind: root.isWorkspace ? .cargoWorkspace : .cargoPackage,
                role: role,
                name: root.name,
                detail: root.isWorkspace
                    ? (root.packages.count == 1
                        ? String(localized: "1 package")
                        : String(localized: "\(root.packages.count) packages"))
                    : root.packages.first?.manifest.version,
                directory: root.directory,
                relativePath: relativePath(of: root.directory)
            ))
            if role != .thirdParty { cargoRoots.append(root) }
        }
    }
}
