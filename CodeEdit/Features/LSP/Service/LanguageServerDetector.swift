//
//  LanguageServerDetector.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/10/26.
//

import Foundation

/// Detects language servers installed on the user's system.
///
/// CodeEdit does not install language servers itself. Instead, the user's login shell environment
/// (`PATH` and other environment variables) is resolved and searched for the executables of
/// supported language servers. Currently supported servers:
/// - `clangd` (C, C++, Objective-C)
/// - `neocmakelsp` (CMake)
enum LanguageServerDetector {
    /// A language server executable CodeEdit knows how to locate and launch.
    struct SupportedServer {
        /// The name of the executable to search for in the user's `PATH`.
        let executable: String
        /// The LSP language identifiers this server handles.
        let languageIds: [String]
        /// Additional arguments passed to the executable when launching the server.
        let arguments: [String]
    }

    /// All language servers CodeEdit can auto-detect.
    static let supportedServers: [SupportedServer] = [
        SupportedServer(executable: "clangd", languageIds: ["c", "cpp", "objective-c"], arguments: []),
        SupportedServer(executable: "neocmakelsp", languageIds: ["cmake"], arguments: ["stdio"])
    ]

    /// All LSP language identifiers covered by ``supportedServers``.
    static var supportedLanguageIds: [String] {
        supportedServers.flatMap(\.languageIds)
    }

    /// Searches the user's login shell environment for all supported language servers.
    ///
    /// This spawns the user's login shell and may take a moment. Do not call on the main thread.
    /// - Returns: A map of LSP language identifiers to the detected server binaries.
    static func detectServers() -> [String: LanguageServerBinary] {
        let environment = userShellEnvironment()
        // Drop paths that resolve in the shell but don't point at an executable file.
        let executablePaths = locateExecutables(supportedServers.map(\.executable))
            .filter { FileManager.default.isExecutableFile(atPath: $0.value) }

        var configurations: [String: LanguageServerBinary] = [:]
        for server in supportedServers {
            guard let execPath = executablePaths[server.executable] else { continue }
            let binary = LanguageServerBinary(execPath: execPath, args: server.arguments, env: environment)
            for languageId in server.languageIds {
                configurations[languageId] = binary
            }
        }
        return configurations
    }

    // MARK: - Shell Environment

    /// Captures the environment variables of the user's login shell.
    ///
    /// Apps launched from the GUI on macOS receive a minimal environment, so the user's login
    /// shell is spawned to resolve their real `PATH` and other variables. Falls back to the
    /// app's own environment if the shell cannot be run.
    /// - Returns: The user's environment variables.
    static func userShellEnvironment() -> [String: String] {
        guard let output = try? runInLoginShell("/usr/bin/env") else {
            return ProcessInfo.processInfo.environment
        }

        var environment: [String: String] = [:]
        for line in output.split(separator: "\n") {
            guard let separatorIndex = line.firstIndex(of: "=") else { continue }
            let key = line[..<separatorIndex]
            guard isValidEnvironmentKey(key) else { continue }
            environment[String(key)] = String(line[line.index(after: separatorIndex)...])
        }
        return environment.isEmpty ? ProcessInfo.processInfo.environment : environment
    }

    /// Locates the given executables in the user's login shell `PATH`.
    /// - Parameter names: The executable names to search for.
    /// - Returns: A map of executable names to their absolute paths. Missing executables are omitted.
    static func locateExecutables(_ names: [String]) -> [String: String] {
        guard !names.isEmpty,
              let output = try? runInLoginShell(names.map { "command -v \($0)" }.joined(separator: "; ")) else {
            return [:]
        }

        var results: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let path = line.trimmingCharacters(in: .whitespaces)
            let executable = (path as NSString).lastPathComponent
            guard path.hasPrefix("/"), names.contains(executable) else { continue }
            results[executable] = path
        }
        return results
    }

    /// Runs a command in the user's login shell and returns its standard output.
    ///
    /// Runs in a login shell so files such as `.zprofile` and `.zshrc` are sourced,
    /// matching the environment the user has in their terminal.
    /// - Parameter command: The command to run.
    /// - Returns: The standard output of the command.
    private static func runInLoginShell(_ command: String) throws -> String {
        let shellPath = Shell.autoDetectDefaultShell()
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        // Discard standard error so shell profile noise doesn't pollute the output
        task.standardError = FileHandle.nullDevice
        task.arguments = ["-lic", command]
        task.executableURL = URL(
            fileURLWithPath: shellPath.hasPrefix("/") ? shellPath : Shell.zsh.defaultPath
        )
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(bytes: data, encoding: .utf8) else {
            throw ShellClientError.failedToDecodeOutput
        }
        return output
    }

    /// Whether the string is a valid environment variable name.
    private static func isValidEnvironmentKey(_ key: Substring) -> Bool {
        guard let first = key.first, first.isLetter || first == "_" else { return false }
        return key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
