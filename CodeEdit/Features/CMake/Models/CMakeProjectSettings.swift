//
//  CMakeProjectSettings.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/30/26.
//

import Foundation

/// Per-workspace CMake settings edited in the project editor and stored in
/// `.codeedit/cmake-settings.json`.
///
/// Every optional value means "let CMake (or the active configure preset) decide", so an empty
/// settings file changes nothing but the build type. When a configure preset is selected, the
/// preset keeps control of the generator, build directory, compilers, build type, and language
/// standard; ``variables`` and ``run`` always apply.
///
/// Decoding is lenient: every key falls back to its default when it is missing or has the wrong
/// type, so a hand-edited file never discards the rest of the settings.
struct CMakeProjectSettings: Codable, Equatable, Sendable {
    /// The file name inside the workspace's `.codeedit` folder.
    static let fileName = "cmake-settings.json"

    var toolchain = Toolchain()
    var build = Build()
    /// Extra `-D` cache definitions passed to every configure step, in order.
    var variables: [KeyValue] = []
    var run = Run()

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolchain = container.lenient(Toolchain.self, forKey: .toolchain) ?? Toolchain()
        build = container.lenient(Build.self, forKey: .build) ?? Build()
        variables = container.lenient([KeyValue].self, forKey: .variables) ?? []
        run = container.lenient(Run.self, forKey: .run) ?? Run()
    }

    /// Compilers and the build-system generator.
    struct Toolchain: Codable, Equatable, Sendable {
        /// Absolute path passed as `CMAKE_C_COMPILER`, or `nil` for CMake's default.
        var cCompiler: String?
        /// Absolute path passed as `CMAKE_CXX_COMPILER`, or `nil` for CMake's default.
        var cxxCompiler: String?
        /// The `-G` generator name, or `nil` for CMake's default.
        var generator: String?

        init(cCompiler: String? = nil, cxxCompiler: String? = nil, generator: String? = nil) {
            self.cCompiler = cCompiler
            self.cxxCompiler = cxxCompiler
            self.generator = generator
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            cCompiler = container.lenient(String.self, forKey: .cCompiler)?.nonEmpty
            cxxCompiler = container.lenient(String.self, forKey: .cxxCompiler)?.nonEmpty
            generator = container.lenient(String.self, forKey: .generator)?.nonEmpty
        }
    }

    /// Build type, output location, and language standard.
    struct Build: Codable, Equatable, Sendable {
        /// The default build directory, relative to the source directory.
        static let defaultBuildDirectory = "build"

        var configuration: CMakeBuildConfiguration = .debug
        /// The build directory; relative paths resolve against the source directory.
        var buildDirectory: String = Self.defaultBuildDirectory
        /// The value passed as `CMAKE_CXX_STANDARD`, or `nil` to leave it to the project.
        var cxxStandard: CMakeCXXStandard?

        init(
            configuration: CMakeBuildConfiguration = .debug,
            buildDirectory: String = Self.defaultBuildDirectory,
            cxxStandard: CMakeCXXStandard? = nil
        ) {
            self.configuration = configuration
            self.buildDirectory = buildDirectory
            self.cxxStandard = cxxStandard
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            configuration = container.lenient(CMakeBuildConfiguration.self, forKey: .configuration) ?? .debug
            buildDirectory = container.lenient(String.self, forKey: .buildDirectory)?.nonEmpty
                ?? Self.defaultBuildDirectory
            cxxStandard = container.lenient(CMakeCXXStandard.self, forKey: .cxxStandard)
        }
    }

    /// What the debugger launches.
    struct Run: Codable, Equatable, Sendable {
        /// The CMake executable target to launch, by name.
        var targetName: String?
        /// An explicit executable path; takes precedence over ``targetName``.
        var customExecutable: String?
        /// The working directory; relative paths resolve against the source directory.
        /// `nil` uses the source directory.
        var workingDirectory: String?
        /// Command-line arguments, split with shell-style quoting (see ``CommandLineArguments``).
        var arguments: String = ""
        /// Environment variables added to the debuggee's environment.
        var environment: [KeyValue] = []

        init(
            targetName: String? = nil,
            customExecutable: String? = nil,
            workingDirectory: String? = nil,
            arguments: String = "",
            environment: [KeyValue] = []
        ) {
            self.targetName = targetName
            self.customExecutable = customExecutable
            self.workingDirectory = workingDirectory
            self.arguments = arguments
            self.environment = environment
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            targetName = container.lenient(String.self, forKey: .targetName)?.nonEmpty
            customExecutable = container.lenient(String.self, forKey: .customExecutable)?.nonEmpty
            workingDirectory = container.lenient(String.self, forKey: .workingDirectory)?.nonEmpty
            arguments = container.lenient(String.self, forKey: .arguments) ?? ""
            environment = container.lenient([KeyValue].self, forKey: .environment) ?? []
        }
    }

    /// A named value that can be switched off without deleting it; used for CMake definitions
    /// and environment variables.
    struct KeyValue: Codable, Equatable, Identifiable, Sendable {
        /// Identifies the row in editing UI; not persisted.
        var id = UUID()
        var isEnabled = true
        var name: String
        var value: String

        init(name: String = "", value: String = "", isEnabled: Bool = true) {
            self.name = name
            self.value = value
            self.isEnabled = isEnabled
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            isEnabled = container.lenient(Bool.self, forKey: .isEnabled) ?? true
            name = container.lenient(String.self, forKey: .name) ?? ""
            value = container.lenient(String.self, forKey: .value) ?? ""
        }

        enum CodingKeys: String, CodingKey {
            case isEnabled = "enabled", name, value
        }
    }
}

/// The single-configuration build types CMake defines.
enum CMakeBuildConfiguration: String, Codable, CaseIterable, Identifiable, Sendable {
    case debug = "Debug"
    case release = "Release"
    case relWithDebInfo = "RelWithDebInfo"
    case minSizeRel = "MinSizeRel"

    var id: String { rawValue }
}

/// C++ standards offered by the project editor, stored as the `CMAKE_CXX_STANDARD` value.
enum CMakeCXXStandard: String, Codable, CaseIterable, Identifiable, Sendable {
    case cxx17 = "17"
    case cxx20 = "20"
    case cxx23 = "23"

    var id: String { rawValue }
    var title: String { "C++\(rawValue)" }
}

/// Build-system generators offered by the project editor.
enum CMakeGenerator: String, CaseIterable, Identifiable, Sendable {
    case ninja = "Ninja"
    case ninjaMultiConfig = "Ninja Multi-Config"
    case unixMakefiles = "Unix Makefiles"
    case xcode = "Xcode"

    var id: String { rawValue }

    /// The tool the generator drives, which must be installed for builds to work.
    var buildTool: String {
        switch self {
        case .ninja, .ninjaMultiConfig: "ninja"
        case .unixMakefiles: "make"
        case .xcode: "xcodebuild"
        }
    }

    /// Whether a generator name produces a multi-configuration build tree, where the build type
    /// is chosen at build time with `--config` instead of `CMAKE_BUILD_TYPE`.
    static func isMultiConfig(_ name: String?) -> Bool {
        name == "Xcode" || name == "Ninja Multi-Config" || name?.hasPrefix("Visual Studio ") == true
    }
}

// MARK: - Decoding helpers

private extension KeyedDecodingContainer {
    /// Decodes a value, treating a missing key or a type mismatch as absent.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}

private extension String {
    /// The string with surrounding whitespace removed, or `nil` when nothing is left.
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
