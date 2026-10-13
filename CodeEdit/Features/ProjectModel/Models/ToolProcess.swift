//
//  ToolProcess.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

/// Runs a command-line tool to completion and collects its output, for probes such as
/// `cmake --version` or `flutter devices --machine`.
///
/// Blocks the calling thread; call it off the main actor.
enum ToolProcess {
    /// What a finished tool printed.
    struct Result: Equatable, Sendable {
        var status: Int32
        /// Standard output.
        var output: String
        /// Standard error.
        var errorOutput: String

        /// Whether the tool exited with status 0.
        var succeeded: Bool { status == 0 }
    }

    /// Runs `executable` with `arguments`, killing it after `timeout`.
    /// - Parameters:
    ///   - executable: An absolute path.
    ///   - arguments: Arguments passed as they are, without a shell.
    ///   - directory: The working directory.
    ///   - environment: The process environment, normally the login shell's.
    ///   - timeout: How long to wait before terminating the tool.
    /// - Returns: The result, or `nil` when the tool could not be started or timed out.
    static func run(
        _ executable: String,
        _ arguments: [String],
        in directory: URL? = nil,
        environment: [String: String],
        timeout: TimeInterval = 20
    ) -> Result? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        if let directory { process.currentDirectoryURL = directory }
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        // Drain both pipes while the tool runs so a chatty tool cannot block on a full pipe.
        let group = DispatchGroup()
        let output = Collector()
        let errorOutput = Collector()
        DispatchQueue.global(qos: .utility).async(group: group) {
            output.data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        }
        DispatchQueue.global(qos: .utility).async(group: group) {
            errorOutput.data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 2)
            return nil
        }
        _ = group.wait(timeout: .now() + 2)
        return Result(
            status: process.terminationStatus,
            output: String(bytes: output.data, encoding: .utf8) ?? "",
            errorOutput: String(bytes: errorOutput.data, encoding: .utf8) ?? ""
        )
    }

    /// Holds one pipe's data; written once by its reader, read after the group finishes.
    private final class Collector: @unchecked Sendable {
        var data = Data()
    }
}
