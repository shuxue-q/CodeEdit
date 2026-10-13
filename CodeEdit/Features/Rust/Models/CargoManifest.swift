//
//  CargoManifest.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

/// A parsed `Cargo.toml`: package metadata, workspace layout, explicit targets, features,
/// dependencies and profiles.
///
/// Read with ``TOMLDocument``; nothing runs `cargo`. Targets Cargo discovers from the file layout
/// (`src/main.rs`, `examples/*.rs`, …) are added by ``CargoPackage/load(manifest:)``.
struct CargoManifest: Equatable, Sendable {
    /// The file name of a Cargo manifest.
    static let fileName = "Cargo.toml"

    /// The `name` of the `[package]` table, if any.
    var packageName: String?
    /// The package version, or `nil` when unset or inherited.
    var version: String?
    /// The Rust edition, such as `2021`.
    var edition: String?
    /// The minimum supported Rust version (`rust-version`).
    var rustVersion: String?
    /// The package description.
    var description: String?
    /// Whether the package may be published; `false` for `publish = false` or an empty registry list.
    var publish = true
    /// The `build` key: a build script path, or `nil` to use `build.rs` when present.
    var buildScript: String?
    /// Whether `build = false` turns build script discovery off.
    var buildScriptDisabled = false
    /// `[package]` keys inherited from the workspace (`version.workspace = true`).
    var inheritedKeys: [String] = []
    /// `autobins`, `autoexamples`, `autotests`, `autobenches`; missing keys default to `true`.
    var autoDiscovery = AutoDiscovery()

    /// Whether the manifest has a `[workspace]` table.
    var isWorkspace = false
    /// The `members` of the `[workspace]` table: relative paths or globs.
    var workspaceMembers: [String] = []
    /// The `exclude` list of the `[workspace]` table: relative paths of directories that are not members.
    var workspaceExclude: [String] = []
    /// The workspace's `resolver`.
    var resolver: String?

    /// The `[lib]` table, when present.
    var library: CargoTarget?
    /// Targets declared with `[[bin]]`, `[[example]]`, `[[test]]` and `[[bench]]`.
    var declaredTargets: [CargoTarget] = []
    /// Features in file order, with what each enables. `default` is included when declared.
    var features: [CargoFeature] = []
    /// Dependencies of all kinds, including target-specific ones.
    var dependencies: [CargoDependency] = []
    /// Profiles declared in the manifest (`[profile.release]`, custom profiles).
    var profiles: [CargoProfile] = []
    /// Problems the TOML reader reported.
    var parseErrors: [TOMLParseError] = []

    /// Which target kinds Cargo discovers from the file layout.
    struct AutoDiscovery: Equatable, Sendable {
        var bins = true
        var examples = true
        var tests = true
        var benches = true
    }

    /// The features `default` enables.
    var defaultFeatures: [String] {
        features.first { $0.name == "default" }?.enables ?? []
    }

    /// Features other than `default`.
    var namedFeatures: [CargoFeature] {
        features.filter { $0.name != "default" }
    }

    /// Reads the manifest at `url`, or returns `nil` when it cannot be read.
    /// - Parameter url: The `Cargo.toml` file.
    static func read(at url: URL) -> Self? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// Parses the text of a `Cargo.toml`.
    /// - Parameter text: The manifest's contents.
    /// - Returns: What the manifest says about its package and workspace.
    static func parse(_ text: String) -> Self {
        let document = TOMLDocument.parse(text)
        var manifest = Self()
        manifest.parseErrors = document.errors
        let root = document.root
        if let package = root["package"]?.table {
            manifest.readPackage(package)
        }
        if let workspace = root["workspace"]?.table {
            manifest.isWorkspace = true
            manifest.workspaceMembers = workspace["members"]?.strings ?? []
            manifest.workspaceExclude = workspace["exclude"]?.strings ?? []
            manifest.resolver = workspace["resolver"]?.string
        }
        if let lib = root["lib"]?.table {
            manifest.library = CargoTarget(kind: .library, table: lib)
        }
        for kind in [CargoTarget.Kind.binary, .example, .test, .bench] {
            for table in root[kind.manifestKey]?.array?.compactMap(\.table) ?? [] {
                manifest.declaredTargets.append(CargoTarget(kind: kind, table: table))
            }
        }
        manifest.features = (root["features"]?.table?.entries ?? []).map { entry in
            CargoFeature(name: entry.key, enables: entry.value.strings)
        }
        manifest.dependencies = Self.readDependencies(in: root, platform: nil)
        for (platform, value) in root["target"]?.table?.entries ?? [] {
            if let table = value.table {
                manifest.dependencies += Self.readDependencies(in: table, platform: platform)
            }
        }
        manifest.profiles = (root["profile"]?.table?.entries ?? []).compactMap { entry in
            entry.value.table.map { CargoProfile(name: entry.key, table: $0) }
        }
        return manifest
    }

    private mutating func readPackage(_ package: TOMLTable) {
        packageName = package["name"]?.string
        for (key, value) in package.entries where value["workspace"]?.boolean == true {
            inheritedKeys.append(key)
        }
        version = package["version"]?.string
        edition = package["edition"]?.string
        rustVersion = package["rust-version"]?.string
        description = package["description"]?.string
        if let publishFlag = package["publish"]?.boolean {
            publish = publishFlag
        } else if let registries = package["publish"]?.array {
            publish = !registries.isEmpty
        }
        if let build = package["build"] {
            if build.boolean == false {
                buildScriptDisabled = true
            } else {
                buildScript = build.string
            }
        }
        autoDiscovery.bins = package["autobins"]?.boolean ?? true
        autoDiscovery.examples = package["autoexamples"]?.boolean ?? true
        autoDiscovery.tests = package["autotests"]?.boolean ?? true
        autoDiscovery.benches = package["autobenches"]?.boolean ?? true
    }

    private static func readDependencies(in table: TOMLTable, platform: String?) -> [CargoDependency] {
        var dependencies: [CargoDependency] = []
        for kind in CargoDependency.Kind.allCases {
            for (name, value) in table[kind.rawValue]?.table?.entries ?? [] {
                dependencies.append(CargoDependency(name: name, kind: kind, value: value, platform: platform))
            }
        }
        return dependencies
    }
}

/// A Cargo build target: the library, a binary, an example, a test, a bench or the build script.
struct CargoTarget: Equatable, Hashable, Sendable, Identifiable {
    /// The target kinds, in the order the project editor lists them.
    enum Kind: String, CaseIterable, Sendable {
        case library = "lib"
        case binary = "bin"
        case example
        case test
        case bench
        case buildScript = "build-script"

        /// The array-of-tables key in a manifest, such as `bin` for `[[bin]]`.
        var manifestKey: String { rawValue }

        /// A short label for display.
        var title: String {
            switch self {
            case .library: "Library"
            case .binary: "Binary"
            case .example: "Example"
            case .test: "Test"
            case .bench: "Bench"
            case .buildScript: "Build Script"
            }
        }
    }

    var kind: Kind
    /// The target name; `nil` for an unnamed `[lib]` (it takes the package name).
    var name: String?
    /// The source path relative to the package, when declared or discovered.
    var path: String?
    /// The `crate-type` list of a library, such as `["staticlib", "rlib"]`.
    var crateTypes: [String] = []
    /// Features that must be enabled to build the target.
    var requiredFeatures: [String] = []

    var id: String { "\(kind.rawValue):\(name ?? path ?? "")" }

    init(kind: Kind, name: String?, path: String? = nil, crateTypes: [String] = [], requiredFeatures: [String] = []) {
        self.kind = kind
        self.name = name
        self.path = path
        self.crateTypes = crateTypes
        self.requiredFeatures = requiredFeatures
    }

    init(kind: Kind, table: TOMLTable) {
        self.kind = kind
        name = table["name"]?.string
        path = table["path"]?.string
        crateTypes = (table["crate-type"] ?? table["crate_type"])?.strings ?? []
        requiredFeatures = table["required-features"]?.strings ?? []
    }
}

/// A feature and the features or dependencies it enables.
struct CargoFeature: Equatable, Hashable, Sendable, Identifiable {
    var name: String
    var enables: [String]

    var id: String { name }
}

/// A dependency entry from `[dependencies]`, `[dev-dependencies]` or `[build-dependencies]`.
struct CargoDependency: Equatable, Hashable, Sendable, Identifiable {
    /// The dependency table it was declared in.
    enum Kind: String, CaseIterable, Sendable {
        case normal = "dependencies"
        case development = "dev-dependencies"
        case build = "build-dependencies"
    }

    /// Where the dependency comes from.
    enum Source: Equatable, Hashable, Sendable {
        /// A registry version requirement; `nil` when only features or other keys are given.
        case registry(String?)
        case path(String)
        case git(url: String, reference: String?)
        /// `{ workspace = true }`.
        case workspace
    }

    var name: String
    var kind: Kind
    var source: Source
    var isOptional = false
    var features: [String] = []
    /// The `package` key when the dependency is renamed.
    var package: String?
    /// The `cfg(...)` or target triple of a `[target.<platform>.dependencies]` table.
    var platform: String?

    var id: String { "\(kind.rawValue):\(platform ?? ""):\(name)" }

    init(name: String, kind: Kind, source: Source, platform: String? = nil) {
        self.name = name
        self.kind = kind
        self.source = source
        self.platform = platform
    }

    init(name: String, kind: Kind, value: TOMLValue, platform: String?) {
        self.name = name
        self.kind = kind
        self.platform = platform
        guard let table = value.table else {
            source = .registry(value.string)
            return
        }
        if table["workspace"]?.boolean == true {
            source = .workspace
        } else if let path = table["path"]?.string {
            source = .path(path)
        } else if let git = table["git"]?.string {
            source = .git(url: git, reference: table["rev"]?.string ?? table["tag"]?.string ?? table["branch"]?.string)
        } else {
            source = .registry(table["version"]?.string)
        }
        isOptional = table["optional"]?.boolean ?? false
        features = table["features"]?.strings ?? []
        package = table["package"]?.string
    }

    /// A short description of the source for display.
    var sourceDescription: String {
        switch source {
        case .registry(let version): version ?? "*"
        case .path(let path): "path: \(path)"
        case let .git(url, reference): reference.map { "git: \(url) @ \($0)" } ?? "git: \(url)"
        case .workspace: "workspace"
        }
    }
}

/// A `[profile.<name>]` table.
struct CargoProfile: Equatable, Hashable, Sendable, Identifiable {
    /// The profiles every Cargo project has.
    static let builtInNames = ["dev", "release", "test", "bench"]

    var name: String
    var inherits: String?
    var optLevel: String?
    var debug: String?
    var lto: String?
    var panic: String?
    var codegenUnits: Int?
    var strip: String?

    var id: String { name }

    init(name: String) {
        self.name = name
    }

    init(name: String, table: TOMLTable) {
        self.name = name
        inherits = table["inherits"]?.string
        optLevel = table["opt-level"].map(\.displayText)
        debug = table["debug"].map(\.displayText)
        lto = table["lto"].map(\.displayText)
        panic = table["panic"]?.string
        codegenUnits = table["codegen-units"]?.integer
        strip = table["strip"].map(\.displayText)
    }

    /// The settings that differ from Cargo's defaults, for display (`opt-level 3, lto thin`).
    var summary: String {
        let parts: [String?] = [
            inherits.map { "inherits \($0)" },
            optLevel.map { "opt-level \($0)" },
            debug.map { "debug \($0)" },
            lto.map { "lto \($0)" },
            panic.map { "panic \($0)" },
            codegenUnits.map { "codegen-units \($0)" },
            strip.map { "strip \($0)" }
        ]
        return parts.compactMap { $0 }.joined(separator: ", ")
    }

    /// The `cargo` arguments selecting this profile: none for `dev`, `--release` for `release`,
    /// `--profile <name>` otherwise.
    var cargoArguments: [String] {
        switch name {
        case "dev": []
        case "release": ["--release"]
        default: ["--profile", name]
        }
    }
}
