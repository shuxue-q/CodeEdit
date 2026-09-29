//
//  ClangFormat.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/28/26.
//

import Foundation

/// Languages whose file extensions clang-format can format without treating them as C++.
enum ClangFormatLanguage {
    /// Extensions clang-format recognizes. Compared case-insensitively.
    static let extensions: Set<String> = [
        "c", "h", "cc", "cpp", "cxx", "hh", "hpp", "hxx", "inc",
        "m", "mm", "cu", "cuh",
        "java",
        "js", "mjs", "cjs", "jsx",
        "ts", "tsx", "mts", "cts",
        "json",
        "cs",
        "proto",
        "td",
        "sv", "svh", "v", "vh"
    ]

    /// Whether Format Code should be offered for this file.
    static func supports(url: URL?) -> Bool {
        guard let url else { return false }
        return extensions.contains(url.pathExtension.lowercased())
    }
}

/// A failure while locating or running clang-format.
enum ClangFormatError: Error, Equatable {
    /// clang-format is not installed, or it is not on the user's PATH.
    case formatterNotFound
    /// Custom style was selected and no `.clang-format` file was found.
    case missingConfig
    /// clang-format exited with an error. The string is stderr, trimmed.
    case failed(String)
    /// clang-format did not finish within the time limit.
    case timedOut

    /// A sentence suitable for an alert.
    var message: String {
        switch self {
        case .formatterNotFound:
            return "clang-format was not found. Install LLVM or the Xcode Command Line Tools, then try again."
        case .missingConfig:
            return "No .clang-format file was found for this file. " +
                "Add one to the project, or choose a built-in style in Settings → Text Editing."
        case .failed(let detail):
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "clang-format failed." : trimmed
        case .timedOut:
            return "clang-format took too long and was stopped."
        }
    }
}

/// One Format Code request.
struct ClangFormatRequest {
    var source: String
    var style: SettingsData.TextEditingSettings.CodeFormatStyle
    var fileURL: URL?
    /// UTF-8 byte offset of the caret. Passed to clang-format so the caret can be restored.
    var cursorUTF8: Int?
    /// 1-based inclusive line ranges. Empty formats the whole file.
    var lineRanges: [ClosedRange<Int>]
    /// When set, this executable is used instead of searching PATH. Tests pass a known binary.
    var executablePath: String?
}

/// The text clang-format produced, plus the caret it reported.
struct ClangFormatOutput: Equatable {
    var text: String
    /// UTF-8 byte offset into ``text``.
    var cursorUTF8: Int?
}

/// Finds a project clang-format config by walking parent directories.
enum ClangFormatConfig {
    /// File names clang-format itself searches for.
    static let fileNames = [".clang-format", "_clang-format"]

    /// Returns the nearest config file, starting at the directory that contains `fileURL`.
    ///
    /// - Parameter stoppingAt: When set, the search includes this directory and does not go above it.
    static func find(startingAt fileURL: URL, stoppingAt root: URL? = nil) -> URL? {
        let fileManager = FileManager.default
        var directory = fileURL.deletingLastPathComponent().standardizedFileURL
        let stop = root?.standardizedFileURL
        while true {
            for name in fileNames {
                let candidate = directory.appendingPathComponent(name)
                if fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
            if let stop, directory.path == stop.path {
                return nil
            }
            let parent = directory.deletingLastPathComponent().standardizedFileURL
            if parent.path == directory.path {
                return nil
            }
            directory = parent
        }
    }
}

/// Builds the clang-format argument list.
enum ClangFormatCommand {
    /// Arguments for one format request. `configFile` is required for the custom style.
    static func arguments(
        style: SettingsData.TextEditingSettings.CodeFormatStyle,
        fileURL: URL?,
        configFile: URL?,
        cursorUTF8: Int?,
        lineRanges: [ClosedRange<Int>]
    ) -> [String] {
        var arguments = ["--style=\(styleArgument(style: style, configFile: configFile))"]
        if let fileURL {
            arguments.append("--assume-filename=\(fileURL.path)")
        }
        if let cursorUTF8 {
            arguments.append("--cursor=\(cursorUTF8)")
        }
        for range in lineRanges where range.lowerBound > 0 {
            arguments.append("--lines=\(range.lowerBound):\(range.upperBound)")
        }
        return arguments
    }

    /// The `-style=` value. Custom points at the config file that was found.
    static func styleArgument(
        style: SettingsData.TextEditingSettings.CodeFormatStyle,
        configFile: URL?
    ) -> String {
        switch style {
        case .custom:
            guard let configFile else { return "file" }
            return "file:\(configFile.path)"
        default:
            return style.rawValue
        }
    }
}

/// Runs clang-format over a buffer.
enum ClangFormatRunner {
    /// Formats `request.source`. Throws when the tool or a custom config file is missing.
    static func format(_ request: ClangFormatRequest) throws -> ClangFormatOutput {
        let configFile = try resolveConfig(style: request.style, fileURL: request.fileURL)
        guard let executable = request.executablePath ?? ClangFormatLocator.executablePath() else {
            throw ClangFormatError.formatterNotFound
        }
        let arguments = ClangFormatCommand.arguments(
            style: request.style,
            fileURL: request.fileURL,
            configFile: configFile,
            cursorUTF8: request.cursorUTF8,
            lineRanges: request.lineRanges
        )
        let stdout = try run(
            executable: executable,
            arguments: arguments,
            source: request.source,
            workingDirectory: request.fileURL?.deletingLastPathComponent()
        )
        return parseOutput(stdout, requestedCursor: request.cursorUTF8 != nil)
    }

    /// The config file for a custom style, or `nil` for a built-in style.
    static func resolveConfig(
        style: SettingsData.TextEditingSettings.CodeFormatStyle,
        fileURL: URL?
    ) throws -> URL? {
        guard style == .custom else { return nil }
        guard let fileURL, let config = ClangFormatConfig.find(startingAt: fileURL) else {
            throw ClangFormatError.missingConfig
        }
        return config
    }

    /// Splits clang-format's stdout. With `--cursor`, the first line is a JSON object.
    static func parseOutput(_ stdout: String, requestedCursor: Bool) -> ClangFormatOutput {
        guard requestedCursor else {
            return ClangFormatOutput(text: stdout, cursorUTF8: nil)
        }
        let parts = stdout.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let header = parts.first, let cursor = parseCursor(String(header)) else {
            return ClangFormatOutput(text: stdout, cursorUTF8: nil)
        }
        let text = parts.count > 1 ? String(parts[1]) : ""
        return ClangFormatOutput(text: text, cursorUTF8: cursor)
    }

    /// Converts a UTF-8 byte offset to a UTF-16 offset, stopping before a partial character.
    static func utf16Offset(utf8Offset: Int, in text: String) -> Int {
        guard utf8Offset > 0 else { return 0 }
        var remaining = utf8Offset
        var utf16 = 0
        for scalar in text.unicodeScalars {
            let scalarBytes = scalar.utf8.count
            if remaining < scalarBytes {
                break
            }
            remaining -= scalarBytes
            utf16 += scalar.utf16.count
            if remaining == 0 {
                break
            }
        }
        return utf16
    }

    private static func parseCursor(_ line: String) -> Int? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cursor = object["Cursor"] as? NSNumber else {
            return nil
        }
        return cursor.intValue
    }

    private static func run(
        executable: String,
        arguments: [String],
        source: String,
        workingDirectory: URL?
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let workingDirectory, FileManager.default.fileExists(atPath: workingDirectory.path) {
            process.currentDirectoryURL = workingDirectory
        }
        let streams = ProcessStreams()
        process.standardInput = streams.input
        process.standardOutput = streams.output
        process.standardError = streams.error
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }
        try process.run()
        let captured = try streams.exchange(source: source, process: process, finished: finished)
        guard process.terminationStatus == 0 else {
            let detail = String(data: captured.error, encoding: .utf8) ?? ""
            throw ClangFormatError.failed(String(detail.prefix(400)))
        }
        guard let text = String(data: captured.output, encoding: .utf8) else {
            throw ClangFormatError.failed("clang-format returned text that was not valid UTF-8.")
        }
        return text
    }
}

/// Pipes for one clang-format process, read concurrently so a full buffer cannot deadlock the write.
private struct ProcessStreams {
    let input = Pipe()
    let output = Pipe()
    let error = Pipe()

    func exchange(
        source: String,
        process: Process,
        finished: DispatchSemaphore
    ) throws -> (output: Data, error: Data) {
        let outputBuffer = PipeBuffer()
        let errorBuffer = PipeBuffer()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputBuffer.data = output.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorBuffer.data = error.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        do {
            try input.fileHandleForWriting.write(contentsOf: Data(source.utf8))
            try input.fileHandleForWriting.close()
        } catch {
            process.terminate()
            group.wait()
            throw ClangFormatError.failed(error.localizedDescription)
        }
        if finished.wait(timeout: .now() + 30) == .timedOut {
            process.terminate()
            group.wait()
            throw ClangFormatError.timedOut
        }
        group.wait()
        return (outputBuffer.data, errorBuffer.data)
    }
}

/// Locates the clang-format executable and remembers the result.
enum ClangFormatLocator {
    private static let lock = NSLock()
    private static var cachedPath: String?
    private static var didSearch = false

    /// The absolute path of clang-format, or `nil` when it cannot be found.
    ///
    /// The search runs the login shell and may take a moment. Do not call it on the main thread.
    static func executablePath() -> String? {
        lock.lock()
        defer { lock.unlock() }
        if didSearch {
            return cachedPath
        }
        didSearch = true
        if let path = LanguageServerDetector.locateExecutables(["clang-format"])["clang-format"],
           FileManager.default.isExecutableFile(atPath: path) {
            cachedPath = path
            return path
        }
        cachedPath = xcrunFind()
        return cachedPath
    }

    /// `xcrun --find clang-format`, used when the login shell PATH does not contain it.
    private static func xcrunFind() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--find", "clang-format"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0,
              let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
            return nil
        }
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else {
            return nil
        }
        return path
    }
}

/// Mutable buffer filled by a pipe-reading queue.
private final class PipeBuffer: @unchecked Sendable {
    var data = Data()
}
