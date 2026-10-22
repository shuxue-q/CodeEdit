//
//  PubspecParser.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

/// The parts of a `pubspec.yaml` CodeEdit shows and uses: identity, SDK constraints,
/// dependencies, Flutter assets and fonts, and plugin platforms.
struct Pubspec: Equatable, Sendable {
    /// The package name (`name:`).
    var name: String?
    /// The package version (`version:`), such as `1.2.0+3`.
    var version: String?
    /// The package description.
    var description: String?
    /// `publish_to`, such as `none`.
    var publishTo: String?
    /// The Dart SDK constraint (`environment.sdk`).
    var sdkConstraint: String?
    /// The Flutter SDK constraint (`environment.flutter`).
    var flutterConstraint: String?
    /// Whether `dependencies` contains `flutter` (normally `flutter: sdk: flutter`).
    var dependsOnFlutter = false
    /// Platforms whose `flutter.plugin.platforms.<platform>.ffiPlugin` is `true`, in file order.
    var ffiPluginPlatforms: [String] = []
    /// Every platform listed under `flutter.plugin.platforms`, in file order.
    var pluginPlatforms: [PubPluginPlatform] = []
    /// `dependencies`, `dev_dependencies` and `dependency_overrides`, in file order.
    var dependencies: [PubDependency] = []
    /// Entries of `flutter.assets`.
    var assets: [String] = []
    /// Family names of `flutter.fonts`.
    var fontFamilies: [String] = []
    /// `flutter.uses-material-design`.
    var usesMaterialDesign = false
    /// `flutter.generate` (localizations code generation).
    var generatesLocalizations = false

    /// The dependencies of one kind.
    func dependencies(of kind: PubDependency.Kind) -> [PubDependency] {
        dependencies.filter { $0.kind == kind }
    }

    /// Whether any dependency of any kind is named `name`.
    func hasDependency(named name: String) -> Bool {
        dependencies.contains { $0.name == name }
    }
}

/// A dependency declared in `pubspec.yaml`.
struct PubDependency: Equatable, Hashable, Sendable, Identifiable {
    /// The section the dependency is declared in.
    enum Kind: String, CaseIterable, Sendable {
        case normal = "dependencies"
        case development = "dev_dependencies"
        case override = "dependency_overrides"
    }

    /// Where the package comes from.
    enum Source: Equatable, Hashable, Sendable {
        /// A hosted package with its version constraint (`nil` for "any").
        case hosted(String?)
        /// An SDK package, such as `flutter`.
        case sdk(String)
        /// A local folder, relative to the pubspec.
        case path(String)
        /// A git repository with an optional ref and subfolder.
        case git(url: String, ref: String?, path: String?)
    }

    var name: String
    var kind: Kind
    var source: Source

    var id: String { "\(kind.rawValue):\(name)" }

    /// A short description of the source for display.
    var sourceDescription: String {
        switch source {
        case .hosted(let constraint): constraint ?? String(localized: "any")
        case .sdk(let sdk): "sdk: \(sdk)"
        case .path(let path): "path: \(path)"
        case let .git(url, ref, _): ref.map { "git: \(url) @ \($0)" } ?? "git: \(url)"
        }
    }
}

/// A platform under `flutter.plugin.platforms`.
struct PubPluginPlatform: Equatable, Hashable, Sendable {
    var name: String
    var pluginClass: String?
    var isFFIPlugin = false
}

/// Reads `pubspec.yaml` with ``YAMLReader``.
enum PubspecParser {
    /// The pubspec file name.
    static let fileName = "pubspec.yaml"

    /// Parses the contents of a `pubspec.yaml` file.
    /// - Parameter text: The file contents.
    /// - Returns: The recognized keys; missing keys stay `nil` or empty.
    static func parse(_ text: String) -> Pubspec {
        let root = YAMLReader.parse(text)
        var pubspec = Pubspec()
        pubspec.name = root["name"]?.string
        pubspec.version = root["version"]?.string
        pubspec.description = root["description"]?.string
        pubspec.publishTo = root["publish_to"]?.string
        pubspec.sdkConstraint = root["environment"]?["sdk"]?.string
        pubspec.flutterConstraint = root["environment"]?["flutter"]?.string

        for kind in PubDependency.Kind.allCases {
            for (name, value) in root[kind.rawValue]?.mapping?.entries ?? [] {
                pubspec.dependencies.append(PubDependency(name: name, kind: kind, source: source(of: value)))
            }
        }
        pubspec.dependsOnFlutter = pubspec.dependencies.contains {
            $0.kind == .normal && $0.name == "flutter" && $0.source == .sdk("flutter")
        }

        let flutter = root["flutter"]
        pubspec.assets = flutter?["assets"]?.sequence?.compactMap { item in
            item.string ?? item["path"]?.string
        } ?? []
        pubspec.fontFamilies = flutter?["fonts"]?.sequence?.compactMap { $0["family"]?.string } ?? []
        pubspec.usesMaterialDesign = flutter?["uses-material-design"]?.boolean ?? false
        pubspec.generatesLocalizations = flutter?["generate"]?.boolean ?? false
        for (name, value) in flutter?["plugin"]?["platforms"]?.mapping?.entries ?? [] {
            let platform = PubPluginPlatform(
                name: name,
                pluginClass: value["pluginClass"]?.string,
                isFFIPlugin: value["ffiPlugin"]?.boolean ?? false
            )
            pubspec.pluginPlatforms.append(platform)
            if platform.isFFIPlugin { pubspec.ffiPluginPlatforms.append(name) }
        }
        return pubspec
    }

    /// Reads the pubspec in `directory`, or returns `nil` when it has none.
    static func read(in directory: URL) -> Pubspec? {
        let file = directory.standardizedFileURL.appending(path: fileName)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return parse(text)
    }

    private static func source(of value: YAMLNode) -> PubDependency.Source {
        guard let mapping = value.mapping else { return .hosted(value.string) }
        if let sdk = mapping["sdk"]?.string { return .sdk(sdk) }
        if let path = mapping["path"]?.string { return .path(path) }
        if let git = mapping["git"] {
            if let url = git.string { return .git(url: url, ref: nil, path: nil) }
            return .git(url: git["url"]?.string ?? "", ref: git["ref"]?.string, path: git["path"]?.string)
        }
        return .hosted(mapping["version"]?.string)
    }
}
