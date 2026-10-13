//
//  FlutterConfigFiles.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

/// The parts of `analysis_options.yaml` the project editor shows.
struct AnalysisOptions: Equatable, Sendable {
    /// The file name.
    static let fileName = "analysis_options.yaml"

    /// `include:` entries, such as `package:flutter_lints/flutter.yaml`.
    var includes: [String] = []
    /// `analyzer.exclude` globs.
    var excludes: [String] = []
    /// Enabled `analyzer.language` strict modes, such as `strict-casts`.
    var strictModes: [String] = []
    /// `analyzer.errors` severity overrides, in file order.
    var severityOverrides: [(code: String, severity: String)] = []
    /// Lint rules turned on in `linter.rules`.
    var enabledRules: [String] = []
    /// Lint rules turned off in `linter.rules` (map form with `false`).
    var disabledRules: [String] = []

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.includes == rhs.includes && lhs.excludes == rhs.excludes && lhs.strictModes == rhs.strictModes
            && lhs.severityOverrides.map(\.code) == rhs.severityOverrides.map(\.code)
            && lhs.severityOverrides.map(\.severity) == rhs.severityOverrides.map(\.severity)
            && lhs.enabledRules == rhs.enabledRules && lhs.disabledRules == rhs.disabledRules
    }

    /// Parses the text of an `analysis_options.yaml`.
    static func parse(_ text: String) -> Self {
        let root = YAMLReader.parse(text)
        var options = Self()
        options.includes = root["include"]?.strings ?? []
        let analyzer = root["analyzer"]
        options.excludes = analyzer?["exclude"]?.strings ?? []
        options.strictModes = (analyzer?["language"]?.mapping?.entries ?? [])
            .filter { $0.value.boolean == true }
            .map(\.key)
        options.severityOverrides = (analyzer?["errors"]?.mapping?.entries ?? []).map { entry in
            (entry.key, entry.value.string ?? "")
        }
        let rules = root["linter"]?["rules"]
        if let list = rules?.sequence {
            options.enabledRules = list.compactMap(\.string)
        } else if let map = rules?.mapping {
            for (rule, value) in map.entries {
                if value.boolean == false {
                    options.disabledRules.append(rule)
                } else {
                    options.enabledRules.append(rule)
                }
            }
        }
        return options
    }

    /// Reads `analysis_options.yaml` in `directory`, or returns `nil` when there is none.
    static func read(in directory: URL) -> Self? {
        guard let text = try? String(contentsOf: directory.appending(path: fileName), encoding: .utf8) else {
            return nil
        }
        return parse(text)
    }
}

/// The `.metadata` file `flutter create` writes: the project type and the platforms it generated.
struct FlutterMetadata: Equatable, Sendable {
    /// The file name.
    static let fileName = ".metadata"

    /// `project_type`: `app`, `plugin`, `plugin_ffi`, `package`, `module` or `skeleton`.
    var projectType: String?
    /// The Flutter channel the project was created with.
    var channel: String?
    /// Platforms recorded under `migration.platforms`, excluding `root`.
    var platforms: [String] = []

    /// Parses the text of a `.metadata` file.
    static func parse(_ text: String) -> Self {
        let root = YAMLReader.parse(text)
        return Self(
            projectType: root["project_type"]?.string,
            channel: root["version"]?["channel"]?.string,
            platforms: (root["migration"]?["platforms"]?.sequence ?? [])
                .compactMap { $0["platform"]?.string }
                .filter { $0 != "root" }
        )
    }

    /// Reads `.metadata` in `directory`, or returns `nil` when there is none.
    static func read(in directory: URL) -> Self? {
        guard let text = try? String(contentsOf: directory.appending(path: fileName), encoding: .utf8) else {
            return nil
        }
        return parse(text)
    }
}

/// Whether `flutter pub get` has resolved the current pubspec.
enum PubResolutionState: Equatable, Sendable {
    /// `.dart_tool/package_config.json` is newer than `pubspec.yaml` and `pubspec.lock`.
    case upToDate
    /// The pubspec or lock file changed since the last `pub get`.
    case outdated
    /// `pub get` has never run here.
    case missing

    /// Compares the modification dates of the pubspec, lock file and package config in `directory`.
    static func check(in directory: URL) -> Self {
        let fileManager = FileManager.default
        func modified(_ path: String) -> Date? {
            let attributes = try? fileManager.attributesOfItem(atPath: directory.appending(path: path).path)
            return attributes?[.modificationDate] as? Date
        }
        guard let config = modified(".dart_tool/package_config.json") else { return .missing }
        let inputs = [modified(PubspecParser.fileName), modified("pubspec.lock")].compactMap { $0 }
        return inputs.contains { $0 > config } ? .outdated : .upToDate
    }
}

/// The platform folders of a Flutter project.
enum FlutterPlatform: String, CaseIterable, Sendable, Identifiable {
    case android, ios, macos, linux, windows, web

    var id: String { rawValue }

    /// The display name.
    var title: String {
        switch self {
        case .android: "Android"
        case .ios: "iOS"
        case .macos: "macOS"
        case .linux: "Linux"
        case .windows: "Windows"
        case .web: "Web"
        }
    }

    /// The `flutter build` subcommand for the platform.
    var buildCommand: String {
        switch self {
        case .android: "apk"
        case .ios: "ios"
        case .macos: "macos"
        case .linux: "linux"
        case .windows: "windows"
        case .web: "web"
        }
    }

    /// The platforms whose folder exists in `directory`.
    static func present(in directory: URL) -> [Self] {
        allCases.filter { platform in
            var isDirectory: ObjCBool = false
            let path = directory.appending(path: platform.rawValue).path
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    /// The platform this Mac can build and run without a device: macOS.
    static let host: Self = .macos
}

/// What `hook/build.dart` (a native assets build hook) appears to drive, read from its text.
struct NativeAssetsHook: Equatable, Sendable {
    /// The hook file, relative to the package.
    static let relativePath = "hook/build.dart"

    /// Whether the hook mentions CMake.
    var runsCMake = false
    /// Whether the hook mentions Cargo.
    var runsCargo = false

    /// Reads the hook in `directory`, or returns `nil` when the package has none.
    static func read(in directory: URL) -> Self? {
        guard let text = try? String(contentsOf: directory.appending(path: relativePath), encoding: .utf8) else {
            return nil
        }
        let lowered = text.lowercased()
        return Self(runsCMake: lowered.contains("cmake"), runsCargo: lowered.contains("cargo"))
    }
}
