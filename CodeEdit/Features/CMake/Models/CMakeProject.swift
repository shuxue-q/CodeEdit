//
//  CMakeProject.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/11/26.
//

import Foundation

/// Static project information; reading a workspace never executes CMake code.
struct CMakeProject: Sendable {
    let sourceDirectory: URL
    var name: String
    var version: String?
    var languages: [String] = []
    var configurePresets: [CMakePreset] = []
    var buildPresets: [CMakePreset] = []
    var errors: [String] = []

    /// Whether the directory contains a root `CMakeLists.txt` file, marking it as a CMake project.
    static func isCMakeProject(at directory: URL) -> Bool {
        let listFile = directory.standardizedFileURL.appendingPathComponent("CMakeLists.txt")
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: listFile.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    static func load(at directory: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> Self? {
        let directory = directory.standardizedFileURL
        guard isCMakeProject(at: directory) else { return nil }
        var project = Self(sourceDirectory: directory, name: directory.lastPathComponent)
        let listFile = directory.appendingPathComponent("CMakeLists.txt")
        do {
            let metadata = try CMakeListParser.parse(String(contentsOf: listFile, encoding: .utf8))
            project.name = metadata.name ?? project.name
            project.version = metadata.version
            project.languages = metadata.languages
        } catch {
            project.errors.append("CMakeLists.txt: \(error.localizedDescription)")
        }
        do {
            let presets = try CMakePresetsParser.load(at: directory, environment: environment)
            project.configurePresets = presets.configure
            project.buildPresets = presets.build
        } catch {
            project.errors.append(error.localizedDescription)
        }
        return project
    }
}

/// A visible, enabled configure or build preset after inheritance and macro expansion.
struct CMakePreset: Identifiable, Sendable {
    let name: String
    let displayName: String?
    let generator: String?
    let binaryDirectory: String?
    let toolchainFile: String?
    let configurePreset: String?
    let configuration: String?
    let cacheVariables: [String: String]
    let environment: [String: String]

    var id: String { name }
    var title: String { displayName ?? name }
    var cCompiler: String? { cacheVariables["CMAKE_C_COMPILER"] ?? environment["CC"] }
    var cxxCompiler: String? { cacheVariables["CMAKE_CXX_COMPILER"] ?? environment["CXX"] }
    var buildType: String? { cacheVariables["CMAKE_BUILD_TYPE"] }
    var isMultiConfig: Bool {
        generator == "Xcode" || generator == "Ninja Multi-Config" || generator?.hasPrefix("Visual Studio ") == true
    }
}

struct CMakeParseError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
