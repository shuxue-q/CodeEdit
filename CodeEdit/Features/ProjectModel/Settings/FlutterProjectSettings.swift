//
//  FlutterProjectSettings.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

/// Per-workspace Flutter choices edited in the project editor and stored in
/// `.codeedit/flutter-settings.json`. Every optional value means "use Flutter's default".
struct FlutterProjectSettings: ProjectSettingsValue {
    static let fileName = "flutter-settings.json"

    /// The device id passed to `flutter run -d`; `nil` runs on macOS.
    var device: String?
    /// The build mode for run and build tasks.
    var buildMode: FlutterBuildMode = .debug
    /// The entry point passed as `-t`; `nil` uses `lib/main.dart`.
    var target: String?
    /// The flavor passed as `--flavor`.
    var flavor: String?
    /// `--dart-define` entries; disabled rows are kept but not passed.
    var dartDefines: [CMakeProjectSettings.KeyValue] = []
    /// Extra arguments appended to `flutter run`, split with shell-style quoting.
    var runArguments = ""
    /// Whether saving a Dart file hot-reloads a running app.
    var hotReloadOnSave = true
    /// The active native CMake root, relative to the workspace (`.` for the workspace itself).
    var nativeRoot: String?
    /// The platform `flutter build` targets; `nil` builds for macOS.
    var buildPlatform: String?

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        device = container.lenient(String.self, forKey: .device)?.trimmedNonEmpty
        buildMode = container.lenient(FlutterBuildMode.self, forKey: .buildMode) ?? .debug
        target = container.lenient(String.self, forKey: .target)?.trimmedNonEmpty
        flavor = container.lenient(String.self, forKey: .flavor)?.trimmedNonEmpty
        dartDefines = container.lenient([CMakeProjectSettings.KeyValue].self, forKey: .dartDefines) ?? []
        runArguments = container.lenient(String.self, forKey: .runArguments) ?? ""
        hotReloadOnSave = container.lenient(Bool.self, forKey: .hotReloadOnSave) ?? true
        nativeRoot = container.lenient(String.self, forKey: .nativeRoot)?.trimmedNonEmpty
        buildPlatform = container.lenient(String.self, forKey: .buildPlatform)?.trimmedNonEmpty
    }

    /// The `flutter run` / `flutter build` arguments these settings add, after the subcommand.
    var modeArguments: [String] {
        var arguments = ["--\(buildMode.rawValue)"]
        if let target { arguments += ["-t", target] }
        if let flavor { arguments += ["--flavor", flavor] }
        for define in dartDefines where define.isEnabled && !define.name.isEmpty {
            arguments.append("--dart-define=\(define.name)=\(define.value)")
        }
        return arguments
    }
}

/// Flutter's build modes.
enum FlutterBuildMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case debug, profile, release

    var id: String { rawValue }

    /// The display name.
    var title: String { rawValue.capitalized }

    /// Whether the mode supports hot reload (only debug builds keep the JIT compiler).
    var supportsHotReload: Bool { self == .debug }
}

/// Per-workspace Cargo choices edited in the project editor and stored in
/// `.codeedit/cargo-settings.json`, keyed by the Cargo root's path relative to the workspace.
struct CargoProjectSettings: ProjectSettingsValue {
    static let fileName = "cargo-settings.json"

    /// Settings for each Cargo root, keyed by relative path (`.` for the workspace folder).
    var roots: [String: Root] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        roots = container.lenient([String: Root].self, forKey: .roots) ?? [:]
    }

    /// The settings of one root, or the defaults.
    func root(_ relativePath: String) -> Root {
        roots[relativePath] ?? Root()
    }

    /// The choices for one Cargo root.
    struct Root: Codable, Equatable, Sendable {
        /// The profile name: `dev`, `release`, or a custom profile.
        var profile = "dev"
        /// Features passed with `--features`.
        var features: [String] = []
        var allFeatures = false
        var noDefaultFeatures = false
        /// A target triple passed with `--target`; `nil` builds for the host.
        var target: String?
        /// The binary or example `cargo run` starts; `nil` uses the first binary.
        var runTarget: CargoRunTarget?
        /// Arguments passed to the program after `--`, split with shell-style quoting.
        var runArguments = ""
        /// Environment variables for run and test tasks.
        var environment: [CMakeProjectSettings.KeyValue] = []

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            profile = container.lenient(String.self, forKey: .profile)?.trimmedNonEmpty ?? "dev"
            features = container.lenient([String].self, forKey: .features) ?? []
            allFeatures = container.lenient(Bool.self, forKey: .allFeatures) ?? false
            noDefaultFeatures = container.lenient(Bool.self, forKey: .noDefaultFeatures) ?? false
            target = container.lenient(String.self, forKey: .target)?.trimmedNonEmpty
            runTarget = container.lenient(CargoRunTarget.self, forKey: .runTarget)
            runArguments = container.lenient(String.self, forKey: .runArguments) ?? ""
            environment = container.lenient([CMakeProjectSettings.KeyValue].self, forKey: .environment) ?? []
        }

        /// The profile, feature and target arguments shared by build, check, test, clippy and run.
        func buildArguments(profiles: [CargoProfile]) -> [String] {
            var arguments = (profiles.first { $0.name == profile } ?? CargoProfile(name: profile)).cargoArguments
            if allFeatures {
                arguments.append("--all-features")
            } else if !features.isEmpty {
                arguments += ["--features", features.joined(separator: ",")]
            }
            if noDefaultFeatures { arguments.append("--no-default-features") }
            if let target { arguments += ["--target", target] }
            return arguments
        }
    }
}

extension String {
    /// The string with surrounding whitespace removed, or `nil` when nothing is left.
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
