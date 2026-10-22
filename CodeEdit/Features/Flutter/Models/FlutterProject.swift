//
//  FlutterProject.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

/// Static information about a Flutter app or plugin and the CMake projects holding its native
/// code. Reading a workspace never runs `flutter`, `dart` or CMake.
struct FlutterProject: Equatable, Sendable {
    /// The workspace folder holding `pubspec.yaml`.
    let rootDirectory: URL
    /// The parsed `pubspec.yaml`.
    var pubspec: Pubspec
    /// Directories containing a `CMakeLists.txt`, in discovery order (see ``discoverNativeRoots(in:)``).
    var nativeRoots: [URL] = []
    /// The `.metadata` file `flutter create` wrote.
    var metadata: FlutterMetadata?
    /// The analyzer configuration.
    var analysisOptions: AnalysisOptions?
    /// Platform folders present in the project.
    var platforms: [FlutterPlatform] = []
    /// The native assets build hook, when the package has one.
    var nativeAssetsHook: NativeAssetsHook?
    /// Whether `flutter pub get` has resolved the current pubspec.
    var pubState: PubResolutionState = .missing
    /// Whether an `ffigen.yaml` configures binding generation.
    var hasFFIgenConfig = false

    /// The package name, falling back to the folder name.
    var name: String { pubspec.name ?? rootDirectory.lastPathComponent }

    /// Whether the package declares native code for Dart FFI.
    var isFFIPlugin: Bool { !pubspec.ffiPluginPlatforms.isEmpty }

    /// Subdirectories searched for a native `CMakeLists.txt` after the workspace root, in order.
    static let nativeRootCandidates = ["src", "cpp", "native", "linux", "windows", "macos"]

    /// Whether the directory holds a `pubspec.yaml` that depends on the Flutter SDK or declares
    /// an FFI plugin platform.
    /// - Parameter directory: The workspace folder.
    static func isFlutterProject(at directory: URL) -> Bool {
        guard let pubspec = readPubspec(in: directory) else { return false }
        return isFlutter(pubspec)
    }

    /// Reads the project in `directory`, or returns `nil` when it is not a Flutter project.
    /// - Parameter directory: The workspace folder.
    static func load(at directory: URL) -> Self? {
        let directory = directory.standardizedFileURL
        guard let pubspec = readPubspec(in: directory), isFlutter(pubspec) else { return nil }
        var project = Self(rootDirectory: directory, pubspec: pubspec, nativeRoots: discoverNativeRoots(in: directory))
        project.metadata = FlutterMetadata.read(in: directory)
        project.analysisOptions = AnalysisOptions.read(in: directory)
        project.platforms = FlutterPlatform.present(in: directory)
        project.nativeAssetsHook = NativeAssetsHook.read(in: directory)
        project.pubState = PubResolutionState.check(in: directory)
        project.hasFFIgenConfig = FileManager.default.fileExists(atPath: directory.appending(path: "ffigen.yaml").path)
        return project
    }

    /// A short label for the project type: the `.metadata` type, else what the pubspec implies.
    var typeTitle: String {
        switch metadata?.projectType {
        case "app": return String(localized: "App")
        case "plugin": return String(localized: "Plugin")
        case "plugin_ffi": return String(localized: "FFI Plugin")
        case "package": return String(localized: "Package")
        case "module": return String(localized: "Module")
        case let other?: return other
        case nil:
            if isFFIPlugin { return String(localized: "FFI Plugin") }
            return pubspec.pluginPlatforms.isEmpty ? String(localized: "App or Package") : String(localized: "Plugin")
        }
    }

    /// Finds the directories holding a native CMake project.
    ///
    /// The order is the workspace root, then ``nativeRootCandidates``, then `packages/*/src`
    /// sorted by package name. Only directories with a `CMakeLists.txt` file are returned.
    /// - Parameter directory: The workspace folder.
    /// - Returns: Standardized directory URLs; the first is the default active root.
    static func discoverNativeRoots(in directory: URL) -> [URL] {
        let directory = directory.standardizedFileURL
        var candidates = [directory] + nativeRootCandidates.map {
            directory.appending(path: $0, directoryHint: .isDirectory)
        }
        let packages = directory.appending(path: "packages", directoryHint: .isDirectory)
        let packageNames = (try? FileManager.default.contentsOfDirectory(atPath: packages.path)) ?? []
        candidates += packageNames
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { packages.appending(path: $0, directoryHint: .isDirectory).appending(path: "src") }
        return candidates
            .map(\.standardizedFileURL)
            .filter { CMakeProject.isCMakeProject(at: $0) }
    }

    // MARK: - Active native root

    /// The defaults key the user's native root choice is persisted under.
    static func nativeRootSelectionKey(for workspaceDirectory: URL) -> String {
        "flutterNativeRoot-\(workspaceDirectory.standardizedFileURL.path)"
    }

    /// A native root's path relative to the workspace, `"."` for the workspace itself.
    static func relativePath(of nativeRoot: URL, in workspaceDirectory: URL) -> String {
        let root = nativeRoot.standardizedFileURL.path
        let base = workspaceDirectory.standardizedFileURL.path
        if root == base { return "." }
        let prefix = base.hasSuffix("/") ? base : base + "/"
        return root.hasPrefix(prefix) ? String(root.dropFirst(prefix.count)) : root
    }

    /// The user's persisted native root, as a path relative to the workspace: the value in
    /// `.codeedit/flutter-settings.json`, else the one CodeEdit kept in `UserDefaults` before
    /// that file existed.
    static func savedNativeRoot(workspaceDirectory: URL, defaults: UserDefaults = .standard) -> String? {
        if let saved = ProjectSettingsFile<FlutterProjectSettings>.saved(in: workspaceDirectory)?.nativeRoot {
            return saved
        }
        return defaults.string(forKey: nativeRootSelectionKey(for: workspaceDirectory))
    }

    /// Persists the user's native root choice.
    static func saveNativeRoot(_ nativeRoot: URL, workspaceDirectory: URL, defaults: UserDefaults = .standard) {
        defaults.set(
            relativePath(of: nativeRoot, in: workspaceDirectory),
            forKey: nativeRootSelectionKey(for: workspaceDirectory)
        )
    }

    /// Picks the active root: the saved choice while it is still discovered, otherwise the first root.
    static func activeNativeRoot(among roots: [URL], workspaceDirectory: URL, saved: String?) -> URL? {
        if let saved, let match = roots.first(where: { relativePath(of: $0, in: workspaceDirectory) == saved }) {
            return match
        }
        return roots.first
    }

    /// The active native root of a Flutter workspace, for background work such as compilation
    /// database lookup that cannot consult the workspace's ``FlutterWorkspace``.
    /// - Parameters:
    ///   - workspaceDirectory: The workspace folder.
    ///   - defaults: The store the user's choice is persisted in.
    /// - Returns: The active root, or `nil` when the workspace is not a Flutter project or has no
    ///   native CMake project.
    static func activeNativeRoot(workspaceDirectory: URL, defaults: UserDefaults = .standard) -> URL? {
        guard isFlutterProject(at: workspaceDirectory) else { return nil }
        return activeNativeRoot(
            among: discoverNativeRoots(in: workspaceDirectory),
            workspaceDirectory: workspaceDirectory,
            saved: savedNativeRoot(workspaceDirectory: workspaceDirectory, defaults: defaults)
        )
    }

    // MARK: - Private

    private static func isFlutter(_ pubspec: Pubspec) -> Bool {
        pubspec.dependsOnFlutter || !pubspec.ffiPluginPlatforms.isEmpty
    }

    private static func readPubspec(in directory: URL) -> Pubspec? {
        let file = directory.standardizedFileURL.appending(path: PubspecParser.fileName)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return PubspecParser.parse(text)
    }
}
