//
//  LSPService+Detection.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/11/26.
//

import Foundation

extension LSPService {
    /// The LSP language identifiers served by clangd.
    static let clangdLanguageIds: Set<String> = ["c", "cpp", "objective-c"]

    /// Whether the executable at the given path is clangd, accepting versioned binary names
    /// such as `clangd-18` or `clangd-mp-19` in addition to plain `clangd`.
    static func isClangdBinary(execPath: String) -> Bool {
        let name = URL(fileURLWithPath: execPath).lastPathComponent
        return name == "clangd" || name.hasPrefix("clangd-")
    }

    // MARK: - Detection

    /// Re-runs language server detection and updates the cached results.
    ///
    /// Detection spawns the user's login shell, so it can take a moment. Call this again
    /// after the user installs a server.
    /// - Returns: The detected binaries, keyed by LSP language identifier.
    @discardableResult
    func redetectServers() async -> [String: LanguageServerBinary] {
        // Detection spawns the user's login shell, keep it off the main actor
        let configs = await Task.detached(priority: .userInitiated) {
            LanguageServerDetector.detectServers()
        }.value
        detectedConfigs = configs
        detectedServers = configs
        return configs
    }

    /// Builds the binary configuration for a server the user picked in the LSP settings.
    /// - Parameter languageId: The LSP language identifier to find a server for.
    /// - Returns: The binary configuration, or `nil` if the language has no configured server.
    func settingsConfiguredServer(for languageId: String) async -> LanguageServerBinary? {
        guard let configured = Settings[\.lsp.servers][languageId], !configured.path.isEmpty else {
            return nil
        }
        return LanguageServerBinary(
            execPath: configured.path,
            args: configured.arguments,
            env: await shellEnvironment()
        )
    }

    /// Points clangd at the workspace's compilation database for C-family languages.
    ///
    /// For CMake workspaces this generates (or reuses) a `compile_commands.json` via
    /// ``CMakeCompilationDatabase`` and appends `--compile-commands-dir` to the server arguments,
    /// giving clangd real compile flags so completion, diagnostics, and semantic highlighting are
    /// accurate. Non-clangd servers and binaries that already carry a user-supplied
    /// `--compile-commands-dir` argument are left untouched.
    /// - Parameters:
    ///   - binary: The resolved server binary configuration.
    ///   - languageId: The LSP language identifier the server is being started for.
    ///   - workspacePath: The workspace the server is being started in.
    /// - Returns: The binary configuration to launch the server with.
    func compilationDatabaseBinary(
        _ binary: LanguageServerBinary,
        for languageId: String,
        workspacePath: String
    ) async -> LanguageServerBinary {
        guard Self.clangdLanguageIds.contains(languageId),
              Self.isClangdBinary(execPath: binary.execPath),
              !binary.args.contains(where: { $0.hasPrefix("--compile-commands-dir") }),
              let databaseDirectory = await CMakeCompilationDatabase.databaseDirectory(workspacePath: workspacePath)
        else {
            return binary
        }
        logger.info("Passing compilation database to clangd: \(databaseDirectory.path, privacy: .private)")
        return LanguageServerBinary(
            execPath: binary.execPath,
            args: binary.args + ["--compile-commands-dir=\(databaseDirectory.path)"],
            env: binary.env
        )
    }

    /// The user's login shell environment, resolved once and cached.
    private func shellEnvironment() async -> [String: String] {
        if let cachedShellEnvironment {
            return cachedShellEnvironment
        }
        let environment = await Task.detached(priority: .userInitiated) {
            LanguageServerDetector.userShellEnvironment()
        }.value
        cachedShellEnvironment = environment
        return environment
    }
}
