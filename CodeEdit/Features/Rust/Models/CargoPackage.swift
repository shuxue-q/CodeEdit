//
//  CargoPackage.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

/// A Cargo package: its manifest plus the targets Cargo would build, including those it discovers
/// from the file layout.
struct CargoPackage: Equatable, Sendable, Identifiable {
    /// The folder holding the package's `Cargo.toml`.
    let directory: URL
    var manifest: CargoManifest
    /// Every target in display order: library, binaries, examples, tests, benches, build script.
    var targets: [CargoTarget]

    var id: String { directory.path }

    /// The package name, falling back to the folder name.
    var name: String { manifest.packageName ?? directory.lastPathComponent }

    /// The targets of one kind.
    func targets(of kind: CargoTarget.Kind) -> [CargoTarget] {
        targets.filter { $0.kind == kind }
    }

    /// Reads a package from its manifest and discovers its targets. Touches the file system; call
    /// it off the main actor.
    /// - Parameter manifestURL: The package's `Cargo.toml`.
    /// - Returns: The package, or `nil` when the manifest cannot be read or has no `[package]`.
    static func load(manifest manifestURL: URL) -> Self? {
        guard let manifest = CargoManifest.read(at: manifestURL), manifest.packageName != nil else { return nil }
        let directory = manifestURL.deletingLastPathComponent().standardizedFileURL
        let targets = discoverTargets(manifest: manifest, in: directory)
        return Self(directory: directory, manifest: manifest, targets: targets)
    }

    // MARK: - Target discovery

    /// The declared targets merged with the ones Cargo infers from the package layout, following
    /// Cargo's target auto-discovery rules.
    static func discoverTargets(manifest: CargoManifest, in directory: URL) -> [CargoTarget] {
        let packageName = manifest.packageName ?? directory.lastPathComponent
        var targets: [CargoTarget] = []

        if let library = manifest.library {
            var library = library
            library.name = library.name ?? packageName.replacingOccurrences(of: "-", with: "_")
            library.path = library.path ?? "src/lib.rs"
            if library.crateTypes.isEmpty { library.crateTypes = ["lib"] }
            targets.append(library)
        } else if exists("src/lib.rs", in: directory) {
            targets.append(CargoTarget(
                kind: .library,
                name: packageName.replacingOccurrences(of: "-", with: "_"),
                path: "src/lib.rs",
                crateTypes: ["lib"]
            ))
        }

        var binaries = manifest.declaredTargets.filter { $0.kind == .binary }
        if manifest.autoDiscovery.bins {
            if exists("src/main.rs", in: directory) {
                binaries.append(CargoTarget(kind: .binary, name: packageName, path: "src/main.rs"))
            }
            binaries += layoutTargets(.binary, folder: "src/bin", in: directory)
        }
        targets += unique(binaries)

        let automatic: [CargoTarget.Kind: Bool] = [
            .example: manifest.autoDiscovery.examples,
            .test: manifest.autoDiscovery.tests,
            .bench: manifest.autoDiscovery.benches
        ]
        let folders: [CargoTarget.Kind: String] = [.example: "examples", .test: "tests", .bench: "benches"]
        for kind in [CargoTarget.Kind.example, .test, .bench] {
            var found = manifest.declaredTargets.filter { $0.kind == kind }
            if automatic[kind] == true, let folder = folders[kind] {
                found += layoutTargets(kind, folder: folder, in: directory)
            }
            targets += unique(found)
        }

        if !manifest.buildScriptDisabled {
            let path = manifest.buildScript ?? "build.rs"
            if exists(path, in: directory) {
                targets.append(CargoTarget(kind: .buildScript, name: "build-script-build", path: path))
            }
        }
        return targets
    }

    /// `<folder>/*.rs` and `<folder>/*/main.rs`, named after the file or folder.
    private static func layoutTargets(_ kind: CargoTarget.Kind, folder: String, in directory: URL) -> [CargoTarget] {
        let folderURL = directory.appending(path: folder, directoryHint: .isDirectory)
        guard let children = try? FileManager.default.contentsOfDirectory(atPath: folderURL.path) else { return [] }
        return children.sorted().compactMap { child in
            guard !child.hasPrefix(".") else { return nil }
            if child.hasSuffix(".rs") {
                return CargoTarget(kind: kind, name: String(child.dropLast(3)), path: "\(folder)/\(child)")
            }
            if exists("\(folder)/\(child)/main.rs", in: directory) {
                return CargoTarget(kind: kind, name: child, path: "\(folder)/\(child)/main.rs")
            }
            return nil
        }
    }

    /// Keeps the first target of each name (declared targets come first and win).
    private static func unique(_ targets: [CargoTarget]) -> [CargoTarget] {
        var seenNames = Set<String>()
        var seenPaths = Set<String>()
        return targets.filter { target in
            let name = target.name ?? ""
            if seenNames.contains(name) { return false }
            if let path = target.path, seenPaths.contains(path) { return false }
            seenNames.insert(name)
            if let path = target.path { seenPaths.insert(path) }
            return true
        }
    }

    private static func exists(_ relativePath: String, in directory: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let path = directory.appending(path: relativePath).path
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
}

/// A folder `cargo` commands run in: a `[workspace]` manifest with its members, or a standalone
/// package.
struct CargoRoot: Equatable, Sendable, Identifiable {
    /// The folder holding the root `Cargo.toml`.
    let directory: URL
    /// The root manifest.
    var manifest: CargoManifest
    /// The member packages; a standalone package lists itself.
    var packages: [CargoPackage]
    /// The toolchain file rustup uses for this root, if any.
    var toolchainFile: RustToolchainFile?

    var id: String { directory.path }

    /// Whether the root is a Cargo workspace.
    var isWorkspace: Bool { manifest.isWorkspace }

    /// A name for display: the package name of a standalone package, else the folder name.
    var name: String {
        if !isWorkspace, let package = packages.first { return package.name }
        if packages.count == 1, let package = packages.first { return package.name }
        return directory.lastPathComponent
    }

    /// The built-in profiles followed by the custom ones the root manifest declares. Profiles are
    /// only read from the root manifest, as Cargo does in a workspace.
    var profiles: [CargoProfile] {
        var profiles = CargoProfile.builtInNames.map { name in
            manifest.profiles.first { $0.name == name } ?? CargoProfile(name: name)
        }
        profiles += manifest.profiles.filter { !CargoProfile.builtInNames.contains($0.name) }
        return profiles
    }

    /// Binaries and examples that `cargo run` can start, across all member packages.
    var runnableTargets: [CargoRunTarget] {
        packages.flatMap { package in
            (package.targets(of: .binary) + package.targets(of: .example)).compactMap { target in
                target.name.map { CargoRunTarget(package: package.name, kind: target.kind, name: $0) }
            }
        }
    }

    /// Features declared by the member packages, prefixed with the package name when there are
    /// several packages (`pkg/feature`, the form `cargo --features` accepts in a workspace).
    var selectableFeatures: [String] {
        packages.flatMap { package in
            package.manifest.namedFeatures.map { packages.count > 1 ? "\(package.name)/\($0.name)" : $0.name }
        }
    }

    /// Loads a root from its manifest: expands workspace members and finds the toolchain file.
    /// - Parameters:
    ///   - manifestURL: The root `Cargo.toml`.
    ///   - boundary: The workspace folder; the toolchain file search stops there.
    static func load(manifest manifestURL: URL, within boundary: URL) -> Self? {
        guard let manifest = CargoManifest.read(at: manifestURL) else { return nil }
        let directory = manifestURL.deletingLastPathComponent().standardizedFileURL
        var packages: [CargoPackage] = []
        if manifest.packageName != nil, let package = CargoPackage.load(manifest: manifestURL) {
            packages.append(package)
        }
        if manifest.isWorkspace {
            for member in expandMembers(manifest.workspaceMembers, exclude: manifest.workspaceExclude, in: directory) {
                let memberManifest = member.appending(path: CargoManifest.fileName)
                if let package = CargoPackage.load(manifest: memberManifest),
                   !packages.contains(where: { $0.directory == package.directory }) {
                    packages.append(package)
                }
            }
        }
        return Self(
            directory: directory,
            manifest: manifest,
            packages: packages,
            toolchainFile: RustToolchainFile.nearest(to: directory, within: boundary)
        )
    }

    /// Expands workspace `members` entries, which may end in a `*` glob component, into package
    /// folders that hold a `Cargo.toml`, minus the `exclude` entries.
    static func expandMembers(_ members: [String], exclude: [String], in directory: URL) -> [URL] {
        let excluded = Set(exclude.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) })
        var result: [URL] = []
        for member in members {
            let pattern = member.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            for path in expandGlob(pattern, in: directory) where !excluded.contains(path) {
                let url = directory.appending(path: path, directoryHint: .isDirectory).standardizedFileURL
                if CargoProject.hasRootManifest(url), !result.contains(url) {
                    result.append(url)
                }
            }
        }
        return result
    }

    /// Expands a relative path whose components may contain `*` or `?`, one directory level each.
    private static func expandGlob(_ pattern: String, in directory: URL) -> [String] {
        var paths = [""]
        for component in pattern.split(separator: "/").map(String.init) {
            guard component.contains("*") || component.contains("?") || component.contains("[") else {
                paths = paths.map { $0.isEmpty ? component : "\($0)/\(component)" }
                continue
            }
            paths = paths.flatMap { base -> [String] in
                let folder = base.isEmpty ? directory : directory.appending(path: base, directoryHint: .isDirectory)
                let children = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
                return children.sorted()
                    .filter { !$0.hasPrefix(".") && fnmatch(component, $0, 0) == 0 }
                    .map { base.isEmpty ? $0 : "\(base)/\($0)" }
            }
        }
        return paths.filter { !$0.isEmpty }
    }
}

/// A binary or example `cargo run` can start.
struct CargoRunTarget: Equatable, Hashable, Sendable, Identifiable, Codable {
    var package: String
    var kind: CargoTarget.Kind
    var name: String

    var id: String { "\(package)/\(kind.rawValue):\(name)" }

    /// The `cargo run` arguments that select the target.
    var cargoArguments: [String] {
        let selector = kind == .example ? ["--example", name] : ["--bin", name]
        return ["--package", package] + selector
    }

    /// A label such as `omniexam_typst_cli` or `render_demo (example)`.
    var title: String {
        kind == .example ? "\(name) (example)" : name
    }
}

extension CargoTarget.Kind: Codable {}
