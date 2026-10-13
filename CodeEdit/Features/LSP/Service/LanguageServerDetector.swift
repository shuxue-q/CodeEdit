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
/// - `dart` (Dart; the analysis server of the Flutter or Dart SDK, see
///   ``resolveDartExecutable(flutterPath:dartPath:fileManager:)``)
/// - `rust-analyzer` (Rust; the rustup component or a standalone binary, see
///   ``resolveRustAnalyzerExecutable(rustAnalyzerPath:rustupPath:run:)``)
enum LanguageServerDetector {
    /// A language server executable CodeEdit knows how to locate and launch.
    struct SupportedServer {
        /// The name of the executable to search for in the user's `PATH`.
        let executable: String
        /// The LSP language identifiers this server handles.
        let languageIds: [String]
        /// Additional arguments passed to the executable when launching the server.
        let arguments: [String]
        /// How to install the server, shown in the settings when it is not found.
        var installHint: String?
    }

    /// All language servers CodeEdit can auto-detect.
    static let supportedServers: [SupportedServer] = [
        SupportedServer(executable: "clangd", languageIds: ["c", "cpp", "objective-c"], arguments: []),
        SupportedServer(executable: "neocmakelsp", languageIds: ["cmake"], arguments: ["stdio"]),
        SupportedServer(
            executable: "dart",
            languageIds: ["dart"],
            arguments: ["language-server", "--protocol=lsp", "--client-id=codeedit"]
        ),
        SupportedServer(
            executable: "rust-analyzer",
            languageIds: ["rust"],
            arguments: [],
            installHint: "rustup component add rust-analyzer"
        )
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
        // `flutter` is only looked up to find the Dart SDK bundled with Flutter, `rustup` to find the
        // rust-analyzer component's real binary.
        // Drop paths that resolve in the shell but don't point at an executable file.
        let executablePaths = locateExecutables(supportedServers.map(\.executable) + ["flutter", "rustup"])
            .filter { FileManager.default.isExecutableFile(atPath: $0.value) }
        let run: ToolRunner = { path, arguments in runTool(path, arguments: arguments, environment: environment) }

        var configurations: [String: LanguageServerBinary] = [:]
        for server in supportedServers {
            guard let execPath = executablePath(for: server, located: executablePaths, run: run) else { continue }
            let binary = LanguageServerBinary(execPath: execPath, args: server.arguments, env: environment)
            for languageId in server.languageIds {
                configurations[languageId] = binary
            }
        }
        return configurations
    }

    /// Runs a tool and returns its exit status and standard output, or `nil` when it cannot be launched.
    typealias ToolRunner = (_ path: String, _ arguments: [String]) -> (status: Int32, output: String)?

    /// The binary to launch for a server, given the executables found on the login shell `PATH`.
    /// - Parameters:
    ///   - server: The server to launch.
    ///   - located: Executable names mapped to their paths on the `PATH`.
    ///   - run: Runs a tool, for servers whose binary has to be asked whether it works.
    /// - Returns: The path to launch, or `nil` if the server is not installed.
    static func executablePath(
        for server: SupportedServer,
        located: [String: String],
        run: ToolRunner = { _, _ in nil }
    ) -> String? {
        switch server.executable {
        case "dart":
            return resolveDartExecutable(flutterPath: located["flutter"], dartPath: located["dart"])
        case "rust-analyzer":
            return resolveRustAnalyzerExecutable(
                rustAnalyzerPath: located["rust-analyzer"],
                rustupPath: located["rustup"],
                run: run
            )
        default:
            return located[server.executable]
        }
    }

    // MARK: - Dart SDK

    /// Finds the real `dart` binary to run the Dart analysis server with.
    ///
    /// `flutter` and `dart` on the `PATH` are usually symlinks to the Flutter SDK's `bin/flutter` and
    /// `bin/dart` bash launchers. Launching the server through them is slower, prints version-check
    /// noise and may start a download, so when either resolves into a Flutter SDK whose
    /// `bin/cache/dart-sdk/bin/dart` exists, that binary is used. Otherwise `dart` on the `PATH` is used
    /// as found (a standalone Dart SDK's `bin/dart` is the real binary).
    /// - Parameters:
    ///   - flutterPath: The path of `flutter` on the login shell `PATH`, if any.
    ///   - dartPath: The path of `dart` on the login shell `PATH`, if any.
    ///   - fileManager: The file manager used to check the candidates.
    /// - Returns: The path to launch the analysis server with, or `nil` if neither SDK is installed.
    static func resolveDartExecutable(
        flutterPath: String?,
        dartPath: String?,
        fileManager: FileManager = .default
    ) -> String? {
        for launcher in [flutterPath, dartPath].compactMap({ $0 }) {
            if let bundled = flutterBundledDart(launcherPath: launcher, fileManager: fileManager) {
                return bundled
            }
        }
        guard let dartPath, fileManager.isExecutableFile(atPath: dartPath) else { return nil }
        return dartPath
    }

    /// The Dart binary bundled with the Flutter SDK a `flutter` or `dart` launcher belongs to.
    /// - Parameters:
    ///   - launcherPath: The path of a launcher, possibly a symlink into the SDK's `bin` directory.
    ///   - fileManager: The file manager used to check the candidate.
    /// - Returns: `<sdk>/bin/cache/dart-sdk/bin/dart`, or `nil` if the launcher is not in a Flutter SDK
    ///   or the SDK has not downloaded its Dart SDK yet.
    static func flutterBundledDart(launcherPath: String, fileManager: FileManager = .default) -> String? {
        let binDirectory = URL(fileURLWithPath: launcherPath).resolvingSymlinksInPath().deletingLastPathComponent()
        guard binDirectory.lastPathComponent == "bin" else { return nil }
        let candidate = binDirectory
            .appendingPathComponent("cache/dart-sdk/bin/dart")
            .path
        return fileManager.isExecutableFile(atPath: candidate) ? candidate : nil
    }

    // MARK: - rust-analyzer

    /// Finds the `rust-analyzer` binary to launch.
    ///
    /// With rustup, `~/.cargo/bin/rust-analyzer` is a proxy that exists whether or not the component is
    /// installed, and that picks the toolchain of the directory it runs in: a project whose
    /// `rust-toolchain.toml` pins a toolchain without the component fails to start the server even when
    /// the default toolchain has it. So when `rustup` is on the `PATH`, the real binary of the default
    /// toolchain (`rustup which rust-analyzer`) is launched, the way Dart's SDK binary is preferred over its
    /// launcher. Otherwise `rust-analyzer` on the `PATH` is used if `rust-analyzer --version` exits 0;
    /// a non-zero exit is the proxy reporting a missing component.
    /// - Parameters:
    ///   - rustAnalyzerPath: The path of `rust-analyzer` on the login shell `PATH`, if any.
    ///   - rustupPath: The path of `rustup` on the login shell `PATH`, if any.
    ///   - run: Runs a tool and reports its exit status and output.
    /// - Returns: The path to launch, or `nil` if no working `rust-analyzer` is installed.
    static func resolveRustAnalyzerExecutable(
        rustAnalyzerPath: String?,
        rustupPath: String?,
        run: ToolRunner
    ) -> String? {
        if let rustupPath, let result = run(rustupPath, ["which", "rust-analyzer"]), result.status == 0 {
            let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        guard let rustAnalyzerPath,
              let result = run(rustAnalyzerPath, ["--version"]),
              result.status == 0 else {
            return nil
        }
        return rustAnalyzerPath
    }

    /// Runs `path` with `arguments` in `environment` and waits up to ten seconds for it to exit. Only for
    /// tools with a few lines of output.
    /// - Returns: The exit status and standard output, or `nil` if the tool could not be run or hung.
    static func runTool(
        _ path: String,
        arguments: [String],
        environment: [String: String]
    ) -> (status: Int32, output: String)? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        // Outside any project, so rustup answers for the default toolchain, not a directory override.
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        // Wait for the exit before reading: the tools asked here print one line, far below a pipe's buffer.
        guard exited.wait(timeout: .now() + 10) == .success else {
            process.terminate()
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
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
