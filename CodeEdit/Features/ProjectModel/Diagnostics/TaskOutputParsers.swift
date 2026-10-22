//
//  TaskOutputParsers.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

/// The parsers generated tasks can use.
enum TaskOutputParserKind: String, Sendable {
    /// rustc and Cargo diagnostics.
    case cargo
    /// Dart front-end, analyzer, Xcode and native-assets build messages.
    case flutter
    /// Clang, GCC and MSVC messages (CTest output).
    case compiler

    /// A fresh parser of this kind.
    func makeParser(baseDirectory: URL) -> any TaskOutputParser {
        switch self {
        case .cargo: CargoOutputParser(baseDirectory: baseDirectory)
        case .flutter: FlutterOutputParser(baseDirectory: baseDirectory)
        case .compiler: CompilerLineParser(baseDirectory: baseDirectory)
        }
    }
}

/// Turns task output, one line at a time, into problems.
protocol TaskOutputParser {
    /// Reads one line without its line terminator or ANSI escapes and returns the diagnostics it
    /// completed.
    mutating func consume(line: String) -> [CMakeBuildDiagnostic]
    /// Returns any diagnostic still waiting for more lines, at the end of the output.
    mutating func finish() -> [CMakeBuildDiagnostic]
}

extension TaskOutputParser {
    mutating func finish() -> [CMakeBuildDiagnostic] { [] }
}

/// Helpers shared by the parsers.
enum TaskOutputText {
    /// Removes ANSI escape sequences (colors, cursor movement, OSC titles) from `text`.
    static func strippingANSI(_ text: String) -> String {
        guard text.contains("\u{1B}") else { return text }
        var result = ""
        var iterator = text.unicodeScalars.makeIterator()
        while let scalar = iterator.next() {
            guard scalar == "\u{1B}" else {
                result.unicodeScalars.append(scalar)
                continue
            }
            guard let kind = iterator.next() else { break }
            if kind == "[" {
                // CSI: parameters and intermediates, then a final byte in @...~.
                while let next = iterator.next(), !(0x40...0x7E).contains(next.value) {}
            } else if kind == "]" {
                // OSC: up to BEL or ESC \.
                while let next = iterator.next() {
                    if next == "\u{07}" { break }
                    if next == "\u{1B}" { _ = iterator.next(); break }
                }
            }
            // Other two-byte escapes are dropped with their second byte.
        }
        return result
    }

    /// Resolves a printed path against the task's working directory. Absolute paths stay as they are.
    static func resolve(_ path: String, against base: URL) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("/") { return URL(fileURLWithPath: trimmed).standardizedFileURL.path }
        if trimmed.hasPrefix("file://"), let url = URL(string: trimmed) { return url.path }
        return base.appending(path: trimmed).standardizedFileURL.path
    }

    /// The parts of a `path:line:column: severity: message` line.
    struct CompilerMessage: Equatable {
        var path: String
        var line: Int
        var column: Int?
        var severity: String
        var message: String
    }

    /// Matches `path:line:column: severity: message` (Clang, GCC, Swift) and returns its parts.
    static func compilerMessage(_ line: String) -> CompilerMessage? {
        let pattern = #/^(.+?):(\d+):(?:(\d+):)? (fatal error|error|warning|note): (.*)$/#
        guard let match = line.firstMatch(of: pattern) else { return nil }
        return CompilerMessage(
            path: String(match.1),
            line: Int(match.2) ?? 1,
            column: match.3.flatMap { Int($0) },
            severity: String(match.4),
            message: String(match.5)
        )
    }

    static func severity(_ text: String) -> CMakeBuildDiagnostic.Severity? {
        switch text.lowercased() {
        case "error", "fatal error": .error
        case "warning": .warning
        case "note", "info", "context", "help": .note
        default: nil
        }
    }
}

// MARK: - Cargo

/// Reads rustc diagnostics as Cargo prints them in a terminal:
///
/// ```
/// error[E0425]: cannot find value `x` in this scope
///   --> src/lib.rs:10:5
/// ```
///
/// plus test panics (`thread 'name' panicked at src/lib.rs:4:9:` and the message on the next
/// line) and unlocated `error:` lines such as `could not compile`. Paths are relative to the Cargo
/// workspace root, which is the task's working directory.
struct CargoOutputParser: TaskOutputParser {
    let baseDirectory: URL
    private var pending: CMakeBuildDiagnostic?
    private var pendingPanic: CMakeBuildDiagnostic?

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    mutating func consume(line: String) -> [CMakeBuildDiagnostic] {
        var completed: [CMakeBuildDiagnostic] = []
        if var panic = pendingPanic {
            pendingPanic = nil
            let message = line.trimmingCharacters(in: .whitespaces)
            if !message.isEmpty { panic.message = String(localized: "Test panicked: \(message)") }
            completed.append(panic)
            return completed
        }
        if let location = line.firstMatch(of: #/^\s*-->\s+(.+?):(\d+):(\d+)\s*$/#), var diagnostic = pending {
            diagnostic.filePath = TaskOutputText.resolve(String(location.1), against: baseDirectory)
            diagnostic.line = Int(location.2)
            diagnostic.column = Int(location.3)
            pending = nil
            completed.append(diagnostic)
            return completed
        }
        if let header = line.firstMatch(of: #/^(error|warning)(?:\[([A-Za-z0-9_:]+)\])?: (.+)$/#) {
            if let previous = pending.take(), previous.severity == .error {
                completed.append(previous)
            }
            let message = String(header.3)
            guard !Self.isSummary(message) else { return completed }
            pending = CMakeBuildDiagnostic(
                severity: header.1 == "error" ? .error : .warning,
                message: message,
                code: header.2.map(String.init)
            )
            return completed
        }
        if let panic = line.firstMatch(of: #/^thread '(.+?)' panicked at (.+?):(\d+):(\d+):?\s*$/#) {
            pendingPanic = CMakeBuildDiagnostic(
                severity: .error,
                message: String(localized: "Test '\(String(panic.1))' panicked"),
                filePath: TaskOutputText.resolve(String(panic.2), against: baseDirectory),
                line: Int(panic.3),
                column: Int(panic.4)
            )
            return completed
        }
        // A blank line or the next section ends a header that never got a location: keep errors.
        if line.trimmingCharacters(in: .whitespaces).isEmpty,
           let previous = pending.take(), previous.severity == .error {
            completed.append(previous)
        }
        return completed
    }

    mutating func finish() -> [CMakeBuildDiagnostic] {
        [pending.take(), pendingPanic.take()].compactMap { $0 }.filter { $0.severity == .error || $0.filePath != nil }
    }

    /// Count lines that summarize diagnostics already reported.
    private static func isSummary(_ message: String) -> Bool {
        message.contains("generated ") && message.contains(" warning")
            || message.hasPrefix("aborting due to")
            || message.hasPrefix("build failed, waiting for other jobs")
    }
}

// MARK: - Flutter

/// Reads the messages `flutter` tasks print:
///
/// - Dart front end: `lib/main.dart:10:5: Error: Expected ';' after this.`
/// - analyzer: `  error • Undefined name 'x' • lib/main.dart:10:5 • undefined_identifier`
/// - Clang and Swift through Xcode or a native assets hook: `/path/file.cc:3:1: error: …`
/// - `Error (Xcode): …` and unlocated `Error: …` lines from the tool itself.
struct FlutterOutputParser: TaskOutputParser {
    let baseDirectory: URL
    /// An analyzer message the terminal width wrapped onto several lines, joined so far.
    private var wrappedAnalyzerMessage: String?
    private var wrappedLineCount = 0

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    mutating func consume(line: String) -> [CMakeBuildDiagnostic] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // `flutter analyze` wraps long messages to the terminal width, indenting the rest; join
        // the lines until the location and code arrive.
        if let partial = wrappedAnalyzerMessage {
            wrappedAnalyzerMessage = nil
            if line.first == " " && !trimmed.isEmpty && wrappedLineCount < 8 {
                let joined = partial + " " + trimmed
                if let diagnostic = analyzerDiagnostic(joined) { return [diagnostic] }
                wrappedAnalyzerMessage = joined
                wrappedLineCount += 1
                return []
            }
        }
        if trimmed.firstMatch(of: #/^(error|warning|info) • /#) != nil, analyzerDiagnostic(trimmed) == nil {
            wrappedAnalyzerMessage = trimmed
            wrappedLineCount = 1
            return []
        }
        if let match = trimmed.firstMatch(of: #/^(.+?\.dart):(\d+):(\d+): (Error|Warning|Info|Context): (.*)$/#),
           let severity = TaskOutputText.severity(String(match.4)) {
            return [CMakeBuildDiagnostic(
                severity: severity,
                message: String(match.5),
                filePath: TaskOutputText.resolve(String(match.1), against: baseDirectory),
                line: Int(match.2),
                column: Int(match.3)
            )]
        }
        if let diagnostic = analyzerDiagnostic(trimmed) {
            return [diagnostic]
        }
        var body = trimmed
        if let xcode = trimmed.firstMatch(of: #/^(?:Error|Warning) \(Xcode\): (.+)$/#) {
            body = String(xcode.1)
            if TaskOutputText.compilerMessage(body) == nil {
                return [CMakeBuildDiagnostic(severity: trimmed.hasPrefix("Error") ? .error : .warning, message: body)]
            }
        }
        if let message = TaskOutputText.compilerMessage(body),
           let severity = TaskOutputText.severity(message.severity) {
            return [CMakeBuildDiagnostic(
                severity: severity,
                message: message.message,
                filePath: TaskOutputText.resolve(message.path, against: baseDirectory),
                line: message.line,
                column: message.column
            )]
        }
        if let match = trimmed.firstMatch(of: #/^Error: (.+)$/#) {
            return [CMakeBuildDiagnostic(severity: .error, message: String(match.1))]
        }
        return []
    }

    /// Reads `error • message • path:line:column • code`.
    private func analyzerDiagnostic(_ text: String) -> CMakeBuildDiagnostic? {
        guard let match = text.firstMatch(of: #/^(error|warning|info) • (.+) • (.+?):(\d+):(\d+) • (\S+)$/#),
              let severity = TaskOutputText.severity(String(match.1)) else { return nil }
        return CMakeBuildDiagnostic(
            severity: severity,
            message: String(match.2),
            filePath: TaskOutputText.resolve(String(match.3), against: baseDirectory),
            line: Int(match.4),
            column: Int(match.5),
            code: String(match.6)
        )
    }
}

// MARK: - Compiler lines

/// Reads Clang, GCC and Swift `path:line:column: severity: message` lines, for CTest output.
struct CompilerLineParser: TaskOutputParser {
    let baseDirectory: URL

    mutating func consume(line: String) -> [CMakeBuildDiagnostic] {
        guard let message = TaskOutputText.compilerMessage(line.trimmingCharacters(in: .whitespaces)),
              let severity = TaskOutputText.severity(message.severity) else { return [] }
        return [CMakeBuildDiagnostic(
            severity: severity,
            message: message.message,
            filePath: TaskOutputText.resolve(message.path, against: baseDirectory),
            line: message.line,
            column: message.column
        )]
    }
}

private extension Optional {
    /// Returns the wrapped value and sets the optional to `nil`.
    mutating func take() -> Wrapped? {
        defer { self = nil }
        return self
    }
}
