//
//  CMakeBuildController.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/14/26.
//

import Foundation
import OSLog

/// Runs `cmake --build` for a workspace and streams compiler diagnostics into the problems panel.
///
/// The build runs with piped stdout/stderr (no pseudo-terminal) so output can be parsed while
/// the build is still running. The build directory and presets come from the workspace's
/// ``CMakeWorkspace`` selection; when the build directory has not been configured yet, a
/// configure step (`cmake --preset …` or `cmake -S … -B …`) runs first, with
/// `CMAKE_EXPORT_COMPILE_COMMANDS=ON` so clangd keeps working afterwards.
///
/// This class is the integration surface for build UI: any control that should trigger a
/// CMake build calls ``start()``.
@MainActor
@Observable
final class CMakeBuildController {
    /// The result of the most recent build attempt.
    enum Outcome: Equatable {
        /// No build has run since the workspace opened.
        case none
        /// The build exited with status 0.
        case success
        /// The build or the preceding configure step exited with a non-zero status.
        case failed(exitCode: Int32)
        /// The user stopped the build.
        case cancelled
    }

    private(set) var isBuilding = false

    private(set) var outcome: Outcome = .none

    /// Diagnostics collected from the current (or most recent) build, in the order they were printed.
    private(set) var diagnostics: [CMakeBuildDiagnostic] = []

    /// A short human-readable description of what the builder is doing, shown next to the problems tab.
    private(set) var statusText = ""

    /// When the most recent build started; used to compute report durations.
    private(set) var lastBuildStartDate: Date?

    /// Raw combined stdout/stderr of the most recent build, truncated to the last
    /// ``logCharacterLimit`` characters. Streamed live to the problems panel while building
    /// and kept for report details afterwards.
    private(set) var lastBuildLog = ""

    /// Invoked on the main actor when a build finishes; the argument is `true` on success.
    var onBuildFinished: ((Bool) -> Void)?

    var errorCount: Int {
        diagnostics.reduce(0) { $0 + ($1.severity == .error ? 1 : 0) }
    }

    var warningCount: Int {
        diagnostics.reduce(0) { $0 + ($1.severity == .warning ? 1 : 0) }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "",
        category: "CMakeBuildController"
    )

    /// Maximum number of characters retained in ``lastBuildLog``; older output is dropped
    /// from the front.
    private static let logCharacterLimit = 200_000

    private let sourceDirectory: URL
    private let workspace: CMakeWorkspace
    private var process: Process?
    private var parser = CMakeBuildOutputParser()
    /// Bumped on every start so completions from a replaced or stopped build are ignored.
    private var generation = 0
    private var stopRequested = false

    init(sourceDirectory: URL, workspace: CMakeWorkspace) {
        self.sourceDirectory = sourceDirectory.standardizedFileURL
        self.workspace = workspace
    }

    // MARK: - Controlling the build

    /// Starts a build, clearing the diagnostics of the previous run. When a build is already
    /// running it is terminated and replaced.
    func start() {
        // Preset discovery is async; building before it finishes would ignore a selected
        // `binaryDir` and fall back to `<source>/build`. Environment detection spawns a
        // login shell and must not run on the main thread.
        // `self` is captured strongly: the task is short-lived and releasing the controller
        // mid-detection is harmless because `beginRun` is generation-guarded.
        Task { @MainActor in
            if workspace.project == nil && !workspace.isLoading {
                workspace.reload()
            }
            await workspace.waitForReload()
            Task.detached(priority: .userInitiated) {
                let environment = LanguageServerDetector.userShellEnvironment()
                let cmake = LanguageServerDetector.locateExecutables(["cmake"])["cmake"]
                await MainActor.run {
                    if let cmake {
                        self.beginRun(cmake: cmake, environment: environment)
                    } else {
                        self.diagnostics = []; self.outcome = .none
                        self.statusText = "CMake was not found in the login shell PATH."
                    }
                }
            }
        }
    }

    /// Starts a build with an explicit CMake executable instead of resolving it from the
    /// user's login shell PATH. Intended for tests.
    /// - Parameters:
    ///   - cmake: The absolute path of the `cmake` executable to run.
    ///   - environment: The environment the build process runs with.
    func start(cmake: String, environment: [String: String] = ProcessInfo.processInfo.environment) {
        beginRun(cmake: cmake, environment: environment)
    }

    /// Stops the running build, if any. The completion handlers observe a cancelled outcome.
    func stop() {
        guard isBuilding else { return }
        stopRequested = true
        process?.terminate()
    }

    /// Removes all collected diagnostics without touching the recorded outcome.
    func clearDiagnostics() {
        diagnostics = []
    }

    // MARK: - Build pipeline

    private func beginRun(cmake: String, environment: [String: String]) {
        generation += 1
        let generation = self.generation
        process?.terminate()
        process = nil
        stopRequested = false
        parser = CMakeBuildOutputParser()
        diagnostics = []
        outcome = .none
        isBuilding = true
        lastBuildStartDate = Date()
        lastBuildLog = ""

        let configurePreset = workspace.configurePreset
        let buildPreset = workspace.buildPreset
        let buildDirectory = CMakeCompilationDatabase.buildDirectory(
            sourceDirectory: sourceDirectory,
            configurePreset: configurePreset
        )
        let request = LaunchRequest(
            executable: cmake,
            currentDirectory: sourceDirectory,
            environment: Self.mergedEnvironment(
                base: environment,
                configurePreset: configurePreset,
                buildPreset: buildPreset
            )
        )
        if CMakeCache.isConfigured(sourceDirectory: sourceDirectory, buildDirectory: buildDirectory) {
            runBuild(request: request, buildDirectory: buildDirectory, buildPreset: buildPreset, generation: generation)
            return
        }
        let cacheFile = buildDirectory.appending(path: "CMakeCache.txt")
        if FileManager.default.fileExists(atPath: cacheFile.path) {
            CMakeCache.invalidateConfiguration(at: buildDirectory)
        }
        configureThenBuild(
            request: request,
            buildDirectory: buildDirectory,
            configurePreset: configurePreset,
            buildPreset: buildPreset,
            generation: generation
        )
    }

    /// Runs the build step itself; shared by direct builds and post-configure builds.
    private func runBuild(
        request: LaunchRequest,
        buildDirectory: URL,
        buildPreset: CMakePreset?,
        generation: Int
    ) {
        statusText = "Building…"
        let arguments = Self.buildArguments(buildDirectory: buildDirectory, buildPreset: buildPreset)
        Self.logger.info("cmake \(arguments.joined(separator: " "))")
        runProcess(request, arguments: arguments, generation: generation) { [weak self] exitCode in
            self?.finishRun(exitCode: exitCode, generation: generation)
        }
    }

    /// Runs a configure step first when the build directory does not exist yet, then the build.
    private func configureThenBuild(
        request: LaunchRequest,
        buildDirectory: URL,
        configurePreset: CMakePreset?,
        buildPreset: CMakePreset?,
        generation: Int
    ) {
        statusText = "Configuring…"
        let arguments = Self.configureArguments(
            sourceDirectory: sourceDirectory,
            buildDirectory: buildDirectory,
            configurePreset: configurePreset
        )
        Self.logger.info("cmake \(arguments.joined(separator: " "))")
        runProcess(request, arguments: arguments, generation: generation) { [weak self] exitCode in
            guard let self, self.generation == generation else { return }
            if exitCode == 0 {
                self.runBuild(
                    request: request,
                    buildDirectory: buildDirectory,
                    buildPreset: buildPreset,
                    generation: generation
                )
            } else {
                self.finishRun(exitCode: exitCode, generation: generation)
            }
        }
    }

    private func finishRun(exitCode: Int32, generation: Int) {
        guard generation == self.generation else { return }
        process = nil
        let remainder = parser.finish()
        if !remainder.isEmpty {
            diagnostics.append(contentsOf: remainder)
        }
        if parser.isTruncated {
            diagnostics.append(CMakeBuildDiagnostic(
                severity: .warning,
                message: "Build output was truncated; only the first "
                    + "\(CMakeBuildOutputParser.maximumDiagnostics) diagnostics are shown."
            ))
        }
        isBuilding = false
        if stopRequested {
            outcome = .cancelled
            statusText = "Build stopped."
        } else if exitCode == 0 {
            outcome = .success
            statusText = "Build succeeded."
        } else {
            outcome = .failed(exitCode: exitCode)
            statusText = "Build failed (exit code \(exitCode))."
        }
        onBuildFinished?(outcome == .success)
    }
}

// MARK: - Process plumbing

extension CMakeBuildController {
    /// Everything needed to launch one CMake process (configure or build step).
    private struct LaunchRequest {
        let executable: String
        let currentDirectory: URL
        let environment: [String: String]
    }

    /// The environment for the CMake process: the user's login shell environment overlaid
    /// with the selected presets' environment (build preset wins over configure preset).
    private static func mergedEnvironment(
        base: [String: String],
        configurePreset: CMakePreset?,
        buildPreset: CMakePreset?
    ) -> [String: String] {
        var environment = base
        configurePreset?.environment.forEach { environment[$0.key] = $0.value }
        buildPreset?.environment.forEach { environment[$0.key] = $0.value }
        return environment
    }

    private static func buildArguments(buildDirectory: URL, buildPreset: CMakePreset?) -> [String] {
        if let buildPreset {
            return ["--build", "--preset", buildPreset.name]
        }
        return ["--build", buildDirectory.path]
    }

    private static func configureArguments(
        sourceDirectory: URL,
        buildDirectory: URL,
        configurePreset: CMakePreset?
    ) -> [String] {
        if let configurePreset {
            return ["--preset", configurePreset.name, "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"]
        }
        return [
            "-S", sourceDirectory.path,
            "-B", buildDirectory.path,
            "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
        ]
    }

    /// Appends streamed process output to ``lastBuildLog``, keeping only the last
    /// ``logCharacterLimit`` characters.
    private func appendLog(_ chunk: String) {
        lastBuildLog += chunk
        if lastBuildLog.count > Self.logCharacterLimit {
            lastBuildLog = String(lastBuildLog.suffix(Self.logCharacterLimit))
        }
    }

    /// Launches a process whose combined output is parsed for diagnostics, then calls
    /// `completion` on the main actor with its exit code.
    private func runProcess(
        _ request: LaunchRequest,
        arguments: [String],
        generation: Int,
        completion: @escaping @MainActor (Int32) -> Void
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: request.executable)
        process.arguments = arguments
        process.currentDirectoryURL = request.currentDirectory
        process.environment = request.environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        self.process = process

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                pipe.fileHandleForReading.readabilityHandler = nil
                return
            }
            let chunk = String(data: data, encoding: .utf8) ?? ""
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                self.appendLog(chunk)
                let found = self.parser.feed(chunk)
                if !found.isEmpty {
                    self.diagnostics.append(contentsOf: found)
                }
            }
        }
        process.terminationHandler = { process in
            pipe.fileHandleForReading.readabilityHandler = nil
            let code: Int32
            if process.terminationReason == .exit {
                code = process.terminationStatus
            } else {
                // Signal terminations surface as their raw status; cancelled builds are
                // labelled by `stopRequested` in `finishRun`.
                code = process.terminationStatus == 0 ? 1 : process.terminationStatus
            }
            Task { @MainActor in
                completion(code)
            }
        }
        do {
            try process.run()
        } catch {
            Self.logger.error("Failed to launch cmake: \(error.localizedDescription)")
            pipe.fileHandleForReading.readabilityHandler = nil
            self.process = nil
            Task { @MainActor in
                completion(1)
            }
        }
    }
}
