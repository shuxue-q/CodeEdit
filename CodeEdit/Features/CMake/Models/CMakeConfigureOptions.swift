//
//  CMakeConfigureOptions.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/30/26.
//

import Foundation

/// The configure and build invocation for a workspace, derived from the selected presets and
/// the project settings. Shared by ``CMakeBuildController`` and ``CMakeCompilationDatabase`` so
/// builds and clangd always use the same build directory and flags.
struct CMakeConfigureOptions: Equatable, Sendable {
    /// What a build has to do before `cmake --build` can run.
    enum Step: Equatable {
        /// The build directory is configured with the current arguments.
        case buildOnly
        /// Run configure (again) in place.
        case configure
        /// Remove the existing cache first, then configure. Needed when the generator changes,
        /// which CMake refuses to do in place, or when the cache belongs to another source tree.
        case configureFromScratch
    }

    let sourceDirectory: URL
    let buildDirectory: URL
    /// Arguments for the configure step, excluding the `cmake` executable.
    let configureArguments: [String]
    /// Arguments for the build step, excluding the `cmake` executable.
    let buildArguments: [String]
    /// The generator explicitly requested by the project settings (never by a preset).
    let requestedGenerator: String?
    /// Whether project settings contributed to the arguments. Without them the arguments are the
    /// ones CodeEdit used before project settings existed.
    let usesProjectSettings: Bool

    /// Builds the invocation.
    /// - Parameters:
    ///   - sourceDirectory: The workspace's source directory.
    ///   - configurePreset: The selected configure preset. When present it controls the
    ///     generator, build directory, compilers, build type, and language standard.
    ///   - buildPreset: The selected build preset, if any.
    ///   - settings: The project settings, or `nil` to use CodeEdit's defaults.
    init(
        sourceDirectory: URL,
        configurePreset: CMakePreset?,
        buildPreset: CMakePreset?,
        settings: CMakeProjectSettings?
    ) {
        let sourceDirectory = sourceDirectory.standardizedFileURL
        self.sourceDirectory = sourceDirectory
        usesProjectSettings = settings != nil

        let buildDirectory: URL
        var configure: [String]
        var generator: String?
        if let configurePreset {
            buildDirectory = CMakeCompilationDatabase.buildDirectory(
                sourceDirectory: sourceDirectory,
                configurePreset: configurePreset
            )
            configure = ["--preset", configurePreset.name, "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"]
            generator = configurePreset.generator
            requestedGenerator = nil
        } else {
            buildDirectory = Self.resolve(
                settings?.build.buildDirectory ?? CMakeProjectSettings.Build.defaultBuildDirectory,
                against: sourceDirectory
            )
            configure = ["-S", sourceDirectory.path, "-B", buildDirectory.path]
            generator = settings?.toolchain.generator
            requestedGenerator = generator
            if let generator { configure += ["-G", generator] }
            configure.append("-DCMAKE_EXPORT_COMPILE_COMMANDS=ON")
            if let settings {
                configure += Self.toolchainDefinitions(settings, multiConfig: CMakeGenerator.isMultiConfig(generator))
            }
        }
        configure += (settings?.variables ?? []).compactMap(Self.definition)
        self.buildDirectory = buildDirectory
        configureArguments = configure

        if let buildPreset {
            buildArguments = ["--build", "--preset", buildPreset.name]
        } else if configurePreset == nil, let settings, CMakeGenerator.isMultiConfig(generator) {
            buildArguments = ["--build", buildDirectory.path, "--config", settings.build.configuration.rawValue]
        } else {
            buildArguments = ["--build", buildDirectory.path]
        }
    }

    /// The `-DNAME=VALUE` argument for an enabled variable with a valid name.
    static func definition(_ variable: CMakeProjectSettings.KeyValue) -> String? {
        guard variable.isEnabled, let name = normalizedName(variable.name) else { return nil }
        return "-D\(name)=\(variable.value)"
    }

    /// Accepts `NAME`, `NAME:TYPE`, and a pasted `-DNAME`; rejects names CMake would misparse.
    static func normalizedName(_ name: String) -> String? {
        var name = name.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("-D") { name.removeFirst(2) }
        guard !name.isEmpty, !name.contains("="), !name.contains(where: \.isWhitespace) else { return nil }
        return name
    }

    /// Resolves a user-entered path: `~` expands to the home directory and relative paths
    /// resolve against `base`.
    static func resolve(_ path: String, against base: URL) -> URL {
        let expanded = (path.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        if expanded.isEmpty { return base.standardizedFileURL }
        if expanded.hasPrefix("/") { return URL(filePath: expanded).standardizedFileURL }
        return base.appending(path: expanded).standardizedFileURL
    }

    private static func toolchainDefinitions(_ settings: CMakeProjectSettings, multiConfig: Bool) -> [String] {
        var definitions: [String] = []
        if !multiConfig {
            definitions.append("-DCMAKE_BUILD_TYPE=\(settings.build.configuration.rawValue)")
        }
        // An empty path is a custom compiler the user has not entered yet.
        let compilers = [
            ("CMAKE_C_COMPILER", settings.toolchain.cCompiler),
            ("CMAKE_CXX_COMPILER", settings.toolchain.cxxCompiler)
        ]
        for case let (name, path?) in compilers where !path.trimmingCharacters(in: .whitespaces).isEmpty {
            let expanded = (path.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
            definitions.append("-D\(name)=\(expanded)")
        }
        if let standard = settings.build.cxxStandard {
            definitions.append("-DCMAKE_CXX_STANDARD=\(standard.rawValue)")
        }
        return definitions
    }

    // MARK: - Deciding whether to configure

    /// Decides what has to happen before building, based on the build directory's cache and
    /// the arguments recorded by the last successful configure.
    func requiredStep() -> Step {
        guard CMakeCache.isConfigured(sourceDirectory: sourceDirectory, buildDirectory: buildDirectory) else {
            let cacheFile = buildDirectory.appending(path: "CMakeCache.txt")
            return FileManager.default.fileExists(atPath: cacheFile.path) ? .configureFromScratch : .configure
        }
        if let requestedGenerator,
           let cachedGenerator = CMakeCache.entries(in: buildDirectory)?["CMAKE_GENERATOR"],
           cachedGenerator != requestedGenerator {
            return .configureFromScratch
        }
        guard let stamp = Self.readStamp(in: buildDirectory) else {
            // Directories configured before CodeEdit recorded stamps (or by hand) are trusted
            // unless the project settings ask for something specific.
            return usesProjectSettings ? .configure : .buildOnly
        }
        return stamp == configureArguments ? .buildOnly : .configure
    }

    /// The file recording the arguments of the last successful configure.
    static func stampFile(in buildDirectory: URL) -> URL {
        buildDirectory.appending(path: "CMakeFiles/codeedit-configure.json")
    }

    /// Records `configureArguments` after a successful configure.
    func writeStamp() {
        guard let data = try? JSONEncoder().encode(configureArguments) else { return }
        try? data.write(to: Self.stampFile(in: buildDirectory), options: .atomic)
    }

    static func readStamp(in buildDirectory: URL) -> [String]? {
        guard let data = try? Data(contentsOf: stampFile(in: buildDirectory)) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }
}
