//
//  ProjectInventory+Links.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

/// Build connections between components, and the configuration files the project editor lists.
extension ProjectInventory {
    // MARK: Links

    mutating func detectLinks() {
        detectHookLinks()
        detectCMakeCargoLinks()
        detectPathDependencyLinks()
    }

    /// A native assets hook that mentions CMake builds the workspace's primary CMake project.
    mutating func detectHookLinks() {
        for package in components where package.kind.toolchain == .flutter && package.role != .thirdParty {
            guard let hook = NativeAssetsHook.read(in: package.directory) else { continue }
            let evidence = relativePath(of: package.directory.appending(path: NativeAssetsHook.relativePath))
            if hook.runsCMake, let cmake = nearestComponent(of: .cmakeProject, to: package.directory) {
                links.append(ProjectLink(
                    source: package.id,
                    target: cmake.id,
                    summary: String(localized: "builds"),
                    evidence: evidence
                ))
            }
            let primaryCargo = components.first { $0.kind.toolchain == .cargo && $0.role == .primary }
            if hook.runsCargo, let cargo = primaryCargo {
                links.append(ProjectLink(
                    source: package.id,
                    target: cargo.id,
                    summary: String(localized: "builds"),
                    evidence: evidence
                ))
            }
        }
    }

    /// A CMake list file that mentions `cargo` and a Cargo root's folder builds that crate.
    mutating func detectCMakeCargoLinks() {
        let cargoComponents = components.filter { $0.kind.toolchain == .cargo && $0.role != .thirdParty }
        guard !cargoComponents.isEmpty else { return }
        for cmake in components where cmake.kind == .cmakeProject && cmake.role != .thirdParty {
            for listFile in Self.listFiles(in: cmake.directory) {
                guard let text = try? String(contentsOf: listFile, encoding: .utf8),
                      text.range(of: "cargo", options: .caseInsensitive) != nil else { continue }
                let linked = Set(links.filter { $0.source == cmake.id }.map(\.target))
                for cargo in cargoComponents where !linked.contains(cargo.id) {
                    let names = [cargo.relativePath, cargo.directory.lastPathComponent]
                        + (cargoRoots.first { $0.directory == cargo.directory }?.packages.map(\.name) ?? [])
                    guard names.contains(where: { $0 != "." && text.contains($0) }) else { continue }
                    links.append(ProjectLink(
                        source: cmake.id,
                        target: cargo.id,
                        summary: String(localized: "builds"),
                        evidence: relativePath(of: listFile)
                    ))
                }
            }
        }
    }

    /// `path:` dependencies in a pubspec point at the package in that folder.
    mutating func detectPathDependencyLinks() {
        for package in components where package.kind.toolchain == .flutter && package.role != .thirdParty {
            guard let pubspec = PubspecParser.read(in: package.directory) else { continue }
            for dependency in pubspec.dependencies {
                guard case .path(let path) = dependency.source else { continue }
                let target = package.directory.appending(path: path, directoryHint: .isDirectory).standardizedFileURL
                guard let dependencyComponent = components.first(where: {
                    $0.kind.toolchain == .flutter && $0.directory == target
                }) else { continue }
                links.append(ProjectLink(
                    source: package.id,
                    target: dependencyComponent.id,
                    summary: String(localized: "depends on"),
                    evidence: relativePath(of: package.directory.appending(path: PubspecParser.fileName))
                ))
            }
        }
    }

    func nearestComponent(of kind: ProjectComponent.Kind, to directory: URL) -> ProjectComponent? {
        components
            .filter { $0.kind == kind && $0.role != .thirdParty }
            .min { lhs, rhs in
                distance(lhs.directory, directory) < distance(rhs.directory, directory)
            }
    }

    func distance(_ lhs: URL, _ rhs: URL) -> Int {
        let left = lhs.pathComponents
        let right = rhs.pathComponents
        let shared = zip(left, right).prefix { $0 == $1 }.count
        return (left.count - shared) + (right.count - shared)
    }

    /// `CMakeLists.txt` and `*.cmake` files of a project, skipping vendored and build folders.
    static func listFiles(in directory: URL) -> [URL] {
        var files: [URL] = []
        var level = [directory]
        for _ in 0..<3 {
            var next: [URL] = []
            for folder in level {
                let list = folder.appending(path: "CMakeLists.txt")
                if FileManager.default.fileExists(atPath: list.path) { files.append(list) }
                next += subfolders(of: folder).filter { !thirdPartyFolderNames.contains($0.lastPathComponent) }
                if files.count >= 60 { return files }
            }
            level = next
        }
        return files
    }

    // MARK: Configuration files

    /// Files the project editor lists, for the workspace's own components.
    static let flutterConfigurationFileNames = [
        PubspecParser.fileName, AnalysisOptions.fileName, "l10n.yaml", "build.yaml", "ffigen.yaml",
        NativeAssetsHook.relativePath, "devtools_options.yaml"
    ]
    static let cmakeConfigurationFileNames = ["CMakeLists.txt", "CMakePresets.json", "CMakeUserPresets.json"]
    static let cargoConfigurationFileNames = [CargoManifest.fileName, ".cargo/config.toml", "build.rs"]

    mutating func collectConfigurationFiles() {
        var files: [ProjectConfigurationFile] = []
        func add(_ toolchain: ProjectToolchain, _ directory: URL, _ names: [String]) {
            for name in names {
                let url = directory.appending(path: name)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let file = ProjectConfigurationFile(toolchain: toolchain, relativePath: relativePath(of: url))
                if !files.contains(file) { files.append(file) }
            }
        }
        for component in components where component.role == .primary || component.role == .member {
            switch component.kind.toolchain {
            case .flutter:
                add(.flutter, component.directory, Self.flutterConfigurationFileNames)
            case .cmake:
                add(.cmake, component.directory, Self.cmakeConfigurationFileNames)
            case .cargo:
                add(.cargo, component.directory, Self.cargoConfigurationFileNames)
                if let root = cargoRoots.first(where: { $0.directory == component.directory }) {
                    for package in root.packages where package.directory != root.directory {
                        add(.cargo, package.directory, [CargoManifest.fileName, "build.rs"])
                    }
                    if let toolchainFile = root.toolchainFile {
                        let folder = toolchainFile.url.deletingLastPathComponent()
                        add(.cargo, folder, [toolchainFile.url.lastPathComponent])
                    }
                }
            }
        }
        configurationFiles = files
    }
}
