//
//  CMakeBuildOutputParser.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/14/26.
//

import Foundation

/// Incrementally turns `cmake --build` output into ``CMakeBuildDiagnostic`` entries.
///
/// Output arrives in arbitrary chunks; ``feed(_:)`` buffers partial lines and only scans
/// complete lines, so diagnostics appear in the problems panel while the build is still
/// running. Supported inputs are the diagnostic formats printed by Clang, GCC, MSVC,
/// CMake itself, Ninja, and Make. Progress lines, source snippets, and caret markers
/// are ignored.
struct CMakeBuildOutputParser: Sendable {
    /// Upper bound of diagnostics kept for one build, guarding against pathological output.
    static let maximumDiagnostics = 4000

    private var buffer = ""
    private var diagnostics: [CMakeBuildDiagnostic] = []
    private var pendingCMakeDiagnostic: Int?
    private(set) var isTruncated = false

    init() {}

    var currentDiagnostics: [CMakeBuildDiagnostic] {
        diagnostics
    }

    /// Appends a chunk of process output and returns the diagnostics completed by it.
    /// - Parameter text: A chunk of stdout or stderr, as decoded from the process pipe.
    /// - Returns: The diagnostics that became complete while scanning this chunk.
    @discardableResult
    mutating func feed(_ text: String) -> [CMakeBuildDiagnostic] {
        buffer.append(text)
        return consumeLines(isEOF: false)
    }

    /// Scans any remaining buffered text without a trailing newline. Call once when the
    /// process output reached end-of-file.
    /// - Returns: The diagnostics completed by flushing the buffer.
    @discardableResult
    mutating func finish() -> [CMakeBuildDiagnostic] {
        consumeLines(isEOF: true)
    }

    // MARK: - Line scanning

    private mutating func consumeLines(isEOF: Bool) -> [CMakeBuildDiagnostic] {
        let countBefore = diagnostics.count
        // Split on the scalar level: a "\r\n" sequence is a single Character, so
        // Character-based splitting would not break lines after a carriage return.
        var lines = buffer.components(separatedBy: "\n")
        if isEOF {
            buffer = ""
        } else {
            // The last element has no trailing newline yet; keep it buffered.
            buffer = lines.popLast() ?? ""
        }
        for var line in lines {
            if line.hasSuffix("\r") { line.removeLast() }
            scan(line)
        }
        if isEOF, !buffer.isEmpty {
            var line = buffer
            if line.hasSuffix("\r") { line.removeLast() }
            scan(line)
            buffer = ""
        }
        return Array(diagnostics[countBefore...])
    }

    private mutating func scan(_ line: String) {
        if continueCMakeBlock(line) { return }
        guard !line.isEmpty, !isNoise(line) else { return }
        if matchLocated(line) { return }
        matchUnlocated(line)
    }

    /// Continues a CMake `at file:line` block with its indented detail lines.
    private mutating func continueCMakeBlock(_ line: String) -> Bool {
        guard let pending = pendingCMakeDiagnostic else { return false }
        if line.hasPrefix("  ") || line.hasPrefix("\t") {
            let detail = line.trimmingCharacters(in: .whitespaces)
            if !detail.isEmpty {
                diagnostics[pending].message.append("\n\(detail)")
            }
            return true
        }
        pendingCMakeDiagnostic = nil
        return line.isEmpty
    }

    /// Progress and decoration lines carry no diagnostic value.
    private func isNoise(_ line: String) -> Bool {
        if line.hasPrefix("[") && line.contains("] ") { return true }
        return line.hasPrefix("ninja: build stopped")
    }

    /// Patterns that carry (or may carry) a source location.
    private mutating func matchLocated(_ line: String) -> Bool {
        if matchCMakeAt(line) { return true }
        if matchClang(line) { return true }
        if matchClangNoColumn(line) { return true }
        return matchMSVC(line)
    }

    /// Patterns without a useful source location.
    private mutating func matchUnlocated(_ line: String) {
        if matchTool(line) { return }
        if matchCMakeInline(line) { return }
        if matchFailed(line) { return }
        matchMake(line)
    }

    // MARK: - Patterns

    /// `path:line:column: severity: message` (Clang and recent GCC).
    private mutating func matchClang(_ line: String) -> Bool {
        guard let groups = Self.match(Self.clangColumn, in: line) else { return false }
        add(
            severity: Self.severity(for: groups[4]),
            message: groups[5],
            filePath: groups[1],
            line: Int(groups[2]),
            column: Int(groups[3])
        )
        return true
    }

    /// `path:line: severity: message` (GCC without columns, Clang notes).
    private mutating func matchClangNoColumn(_ line: String) -> Bool {
        guard let groups = Self.match(Self.clangNoColumn, in: line) else { return false }
        add(
            severity: Self.severity(for: groups[3]),
            message: groups[4],
            filePath: groups[1],
            line: Int(groups[2])
        )
        return true
    }

    /// `path(line,column): warning C4996: message` (MSVC, including clang-cl).
    private mutating func matchMSVC(_ line: String) -> Bool {
        guard let groups = Self.match(Self.msvc, in: line) else { return false }
        add(
            severity: Self.severity(for: groups[4]),
            message: groups[6],
            filePath: groups[1],
            line: Int(groups[2]),
            column: Int(groups[3]),
            code: groups[5].isEmpty ? nil : groups[5]
        )
        return true
    }

    /// `clang: error: linker command failed` and similar tool-level messages.
    private mutating func matchTool(_ line: String) -> Bool {
        guard let groups = Self.match(Self.tool, in: line) else { return false }
        add(severity: Self.severity(for: groups[1]), message: groups[2])
        return true
    }

    /// `CMake Error at file:line (command):` — possibly followed by indented detail lines.
    private mutating func matchCMakeAt(_ line: String) -> Bool {
        guard let groups = Self.match(Self.cmakeAt, in: line) else { return false }
        let severity: CMakeBuildDiagnostic.Severity = groups[1] == "Error" ? .error : .warning
        let message = groups[5]
        append(CMakeBuildDiagnostic(severity: severity, message: message, filePath: groups[2], line: Int(groups[3])))
        if !isTruncated, message.isEmpty || line.hasSuffix(":") {
            pendingCMakeDiagnostic = diagnostics.count - 1
        }
        return true
    }

    /// `CMake Error: message` without a source location.
    private mutating func matchCMakeInline(_ line: String) -> Bool {
        guard let groups = Self.match(Self.cmakeInline, in: line) else { return false }
        let severity: CMakeBuildDiagnostic.Severity = groups[1] == "Error" ? .error : .warning
        append(CMakeBuildDiagnostic(severity: severity, message: groups[2]))
        return true
    }

    /// Ninja's `FAILED: <command>` marker for a failed edge.
    private mutating func matchFailed(_ line: String) -> Bool {
        guard let groups = Self.match(Self.failed, in: line) else { return false }
        let command = groups[1].trimmingCharacters(in: .whitespaces)
        append(CMakeBuildDiagnostic(severity: .error, message: "Build command failed: \(command)"))
        return true
    }

    /// `make: *** [target] Error N`.
    private mutating func matchMake(_ line: String) {
        guard let groups = Self.match(Self.make, in: line) else { return }
        append(CMakeBuildDiagnostic(severity: .error, message: groups[0]))
    }

    // MARK: - Diagnostics assembly

    /// Notes and remarks extend the previous diagnostic when there is one; everything else
    /// becomes its own entry.
    private mutating func add(
        severity: CMakeBuildDiagnostic.Severity,
        message rawMessage: String,
        filePath: String? = nil,
        line: Int? = nil,
        column: Int? = nil,
        code: String? = nil
    ) {
        let message = rawMessage.trimmingCharacters(in: .whitespaces)
        if severity == .note, var previous = diagnostics.last {
            previous.message.append("\n\(message)")
            diagnostics[diagnostics.count - 1] = previous
            return
        }
        var extractedCode = code
        var text = message
        if extractedCode == nil, let bracketed = Self.match(Self.clangCode, in: text), !bracketed[1].isEmpty {
            // Clang appends the activating flag in brackets: `message [-Wunused-variable]`.
            text = bracketed[1]
            extractedCode = bracketed[2]
        }
        append(CMakeBuildDiagnostic(
            severity: severity,
            message: text,
            filePath: filePath,
            line: line,
            column: column,
            code: extractedCode
        ))
    }

    private mutating func append(_ diagnostic: CMakeBuildDiagnostic) {
        guard diagnostics.count < Self.maximumDiagnostics else {
            isTruncated = true
            return
        }
        diagnostics.append(diagnostic)
    }

    private static func severity(for keyword: String) -> CMakeBuildDiagnostic.Severity {
        switch keyword {
        case "error", "fatal error": return .error
        case "warning": return .warning
        default: return .note
        }
    }

    // MARK: - Regular expressions

    private static let clangColumn = compile(
        #"^(.+?):([0-9]+):([0-9]+):\s(fatal error|error|warning|note|remark):\s(.*)$"#
    )
    private static let clangNoColumn = compile(#"^(.+?):([0-9]+):\s(fatal error|error|warning|note|remark):\s(.*)$"#)
    private static let msvc = compile(#"^(.+?)\(([0-9]+)(?:,([0-9]+))?\):\s(fatal error|error|warning|note)"#
        + #"(?:\s+([A-Za-z]+[0-9]+))?:\s(.*)$"#)
    private static let tool = compile(#"^(?:clang|clang\+\+|gcc|g\+\+|cc1|cc1plus|ld|ld\.lld|collect2|ninja):"#
        + #"\s(fatal error|error|warning):\s(.*)$"#)
    private static let cmakeAt = compile(
        #"^CMake\s+(?:(?:Deprecation|Dev)\s+)?(Error|Warning)(?:\s+\((?:dev|deprecated)\))?\s+at\s+(.+?):([0-9]+)"#
            + #"(?:\s+\(([^)]*)\))?:\s*(.*)$"#
    )
    private static let cmakeInline = compile(
        #"^CMake\s+(?:(?:Deprecation|Dev)\s+)?(Error|Warning)(?:\s+\((?:dev|deprecated)\))?:\s(.*)$"#
    )
    private static let failed = compile(#"^FAILED:(.*)$"#)
    private static let make = compile(#"^make(?:\[[0-9]+\])?:\s+\*\*\*.*$"#)
    private static let clangCode = compile(#"^(.*?)\s*\[([A-Za-z0-9=_+-]+)\]$"#)

    /// Compiles a pattern once. A failure here is a programming error: the patterns above are
    /// string literals covered by tests.
    private static func compile(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("Invalid CMake build output pattern \(pattern): \(error)")
        }
    }

    private static func match(_ regex: NSRegularExpression, in line: String) -> [String]? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: line) else { return "" }
            return String(line[range])
        }
    }
}
