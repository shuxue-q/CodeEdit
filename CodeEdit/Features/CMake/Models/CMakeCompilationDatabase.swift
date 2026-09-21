//
//  CMakeCompilationDatabase.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/11/26.
//

import Foundation
import OSLog

/// Generates and locates the `compile_commands.json` compilation database that clangd needs to
/// provide accurate C/C++/Objective-C completion, diagnostics, and semantic highlighting.
///
/// When a C-family file is opened in a CMake workspace, ``LSPService`` asks for the workspace's
/// database directory before starting clangd. An existing database is reused; otherwise CMake is
/// configured once — honoring the configure preset selected in workspace settings — with
/// `CMAKE_EXPORT_COMPILE_COMMANDS=ON`, and the resulting directory is passed to clangd via
/// `--compile-commands-dir`.
enum CMakeCompilationDatabase {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "",
        category: "CMakeCompilationDatabase"
    )

    /// Deduplicates concurrent generation requests for the same workspace, so the C, C++, and
    /// Objective-C servers starting together never trigger multiple CMake configures.
    ///
    /// Successful results are cached for the lifetime of the cache; failed generations are not
    /// cached, so the next request retries (for example after the user installs CMake). Entries
    /// can be dropped explicitly via ``invalidate(_:)`` when the inputs to generation change.
    private actor GenerationCache {
        var tasks: [String: Task<URL?, Never>] = [:]

        func result(
            for sourceDirectory: URL,
            generate: @escaping @Sendable () async -> URL?
        ) async -> URL? {
            if let existing = tasks[sourceDirectory.path] { return await existing.value }
            let task = Task.detached(priority: .userInitiated, operation: generate)
            tasks[sourceDirectory.path] = task
            let result = await task.value
            if result == nil {
                tasks[sourceDirectory.path] = nil
            }
            return result
        }

        func invalidate(_ sourceDirectory: URL) {
            tasks[sourceDirectory.path] = nil
        }

        func reset() {
            tasks.removeAll()
        }
    }

    private static let cache = GenerationCache()

    /// Returns the directory containing the workspace's compilation database, generating one with
    /// CMake when none exists.
    ///
    /// This never throws: any failure (not a CMake project, CMake not installed, configure error)
    /// results in `nil`, and clangd starts without a database as before.
    /// - Parameter workspacePath: The path clangd uses as its workspace root.
    /// - Returns: The directory containing `compile_commands.json`, or `nil` when unavailable.
    static func databaseDirectory(workspacePath: String) async -> URL? {
        let sourceDirectory = URL(filePath: workspacePath).standardizedFileURL
        let listFile = sourceDirectory.appending(path: "CMakeLists.txt")
        guard FileManager.default.fileExists(atPath: listFile.path) else { return nil }
        return await cache.result(for: sourceDirectory) {
            resolve(sourceDirectory: sourceDirectory)
        }
    }

    /// The build directory a configure step uses for the given preset selection.
    /// - Parameters:
    ///   - sourceDirectory: The workspace's source directory.
    ///   - configurePreset: The selected configure preset, if any.
    /// - Returns: The preset's binary directory (relative paths resolve against the source
    ///   directory), or `<source>/build` when no preset is selected.
    static func buildDirectory(sourceDirectory: URL, configurePreset: CMakePreset?) -> URL {
        guard let binaryDirectory = configurePreset?.binaryDirectory, !binaryDirectory.isEmpty else {
            return sourceDirectory.appending(path: "build")
        }
        if binaryDirectory.hasPrefix("/") {
            return URL(filePath: binaryDirectory).standardizedFileURL
        }
        return sourceDirectory.appending(path: binaryDirectory).standardizedFileURL
    }

    /// Clears the deduplication cache. Intended for tests.
    static func resetCache() async {
        await cache.reset()
    }

    /// Drops the cached database directory for a workspace, forcing the next lookup to
    /// locate or generate the database again. Call this when the inputs to generation change,
    /// for example after the user selects a different configure preset.
    /// - Parameter workspacePath: The path clangd uses as its workspace root.
    static func invalidateCache(workspacePath: String) async {
        let sourceDirectory = URL(filePath: workspacePath).standardizedFileURL
        await cache.invalidate(sourceDirectory)
    }

    // MARK: - Private

    /// Locates an existing database or runs CMake configure to produce one. Runs off the main
    /// actor inside a detached task.
    private static func resolve(sourceDirectory: URL) -> URL? {
        let defaultBuildDirectory = sourceDirectory.appending(path: "build")
        let selection = CMakeWorkspace.savedSelection(sourceDirectory: sourceDirectory)

        // Cheap checks first when no preset is selected: no project parsing or shell
        // environment needed. With a selection the preset's binary directory takes
        // precedence over these fallbacks. A database next to a cache from another
        // source tree is ignored so clangd never attaches to foreign compile flags.
        let fallbacks = [sourceDirectory, defaultBuildDirectory]
        if selection.configure.isEmpty, let existing = firstUsableDatabase(in: fallbacks, source: sourceDirectory) {
            return existing
        }

        let environment = LanguageServerDetector.userShellEnvironment()
        let project = CMakeProject.load(at: sourceDirectory, environment: environment)
        let configurePreset = project?.configurePresets.first { $0.name == selection.configure }
        let buildDirectory = Self.buildDirectory(sourceDirectory: sourceDirectory, configurePreset: configurePreset)

        if CMakeCache.isUsableCompilationDatabase(in: buildDirectory, sourceDirectory: sourceDirectory) {
            return buildDirectory
        }

        if let generated = generateDatabase(
            sourceDirectory: sourceDirectory,
            buildDirectory: buildDirectory,
            configurePreset: configurePreset,
            environment: environment
        ) {
            return generated
        }

        // Degrade gracefully: reuse a pre-existing database even if it doesn't match the
        // selected preset — stale compile flags beat no compile flags. A database produced
        // for another source tree is never reused.
        return firstUsableDatabase(in: fallbacks, source: sourceDirectory)
    }

    private static func firstUsableDatabase(in directories: [URL], source: URL) -> URL? {
        directories.first { CMakeCache.isUsableCompilationDatabase(in: $0, sourceDirectory: source) }
    }

    /// Runs CMake configure to produce a compilation database, invalidating a foreign cache first.
    private static func generateDatabase(
        sourceDirectory: URL,
        buildDirectory: URL,
        configurePreset: CMakePreset?,
        environment: [String: String]
    ) -> URL? {
        guard let cmake = LanguageServerDetector.locateExecutables(["cmake"])["cmake"] else {
            logger.info("cmake not found; clangd will run without a compilation database")
            return nil
        }

        let arguments: [String]
        if let configurePreset {
            arguments = ["--preset", configurePreset.name, "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"]
        } else {
            arguments = [
                "-S", sourceDirectory.path,
                "-B", buildDirectory.path,
                "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
            ]
        }
        logger.info("Generating compilation database: cmake \(arguments.joined(separator: " "))")

        var processEnvironment = environment
        configurePreset?.environment.forEach { processEnvironment[$0.key] = $0.value }

        let cacheFile = buildDirectory.appending(path: "CMakeCache.txt")
        if FileManager.default.fileExists(atPath: cacheFile.path),
           !CMakeCache.isConfigured(sourceDirectory: sourceDirectory, buildDirectory: buildDirectory) {
            CMakeCache.invalidateConfiguration(at: buildDirectory)
        }

        if configure(
            cmake: cmake,
            arguments: arguments,
            currentDirectory: sourceDirectory,
            environment: processEnvironment
        ), FileManager.default.fileExists(atPath: databaseFile(in: buildDirectory).path) {
            return buildDirectory
        }
        logger.warning("CMake configure did not produce a compilation database")
        return nil
    }

    private static func databaseFile(in directory: URL) -> URL {
        directory.appending(path: "compile_commands.json")
    }

    /// Runs a CMake configure step, returning whether it exited successfully.
    private static func configure(
        cmake: String,
        arguments: [String],
        currentDirectory: URL,
        environment: [String: String],
        timeout: TimeInterval = 300
    ) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cmake)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Drain the pipe while the process runs: reading only after `waitUntilExit()`
        // deadlocks once the combined output exceeds the pipe buffer (64 KB), because
        // cmake blocks writing while this side blocks waiting for it to exit.
        let output = ProcessOutput()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                pipe.fileHandleForReading.readabilityHandler = nil
            } else {
                output.append(chunk)
            }
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            logger.error("Failed to launch cmake: \(error.localizedDescription)")
            return false
        }

        let watchdog = DispatchWorkItem {
            if process.isRunning {
                logger.warning("CMake configure timed out; terminating")
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        process.waitUntilExit()
        watchdog.cancel()
        pipe.fileHandleForReading.readabilityHandler = nil
        output.append(pipe.fileHandleForReading.readDataToEndOfFile())

        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            logger.warning("cmake configure failed (\(process.terminationStatus)): \(output.string)")
            return false
        }
        return true
    }

    /// Thread-safe accumulation of a process's combined stdout/stderr, written from the
    /// pipe's readability handler queue and read after the process exits.
    private final class ProcessOutput: @unchecked Sendable {
        private var data = Data()
        private let lock = NSLock()

        func append(_ chunk: Data) {
            lock.lock()
            data.append(chunk)
            lock.unlock()
        }

        var string: String {
            lock.lock()
            defer { lock.unlock() }
            return String(data: data, encoding: .utf8) ?? ""
        }
    }
}
