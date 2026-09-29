//
//  CMakeBuildDiagnostic.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/14/26.
//

import Foundation

/// A single compiler or build-system message extracted from `cmake --build` output.
///
/// Instances are produced by ``CMakeBuildOutputParser`` and consumed by the problems panel.
/// `filePath` is kept exactly as printed by the compiler; it may be relative to the build or
/// source directory and is resolved when the user clicks an entry.
struct CMakeBuildDiagnostic: Identifiable, Hashable, Sendable, Codable {
    /// The kind of message, ordered by importance for sorting and counts.
    enum Severity: String, Hashable, Sendable, Comparable, Codable {
        case error
        case warning
        case note

        /// Lower values are more severe; used for sorting within a file.
        var sortOrder: Int {
            switch self {
            case .error: return 0
            case .warning: return 1
            case .note: return 2
            }
        }

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }
    }

    let id: UUID
    var severity: Severity
    var message: String
    var filePath: String?
    var line: Int?
    var column: Int?
    /// The compiler flag or MSVC code when one was printed (for example `-Wunused-variable` or `C4996`).
    var code: String?

    init(
        id: UUID = UUID(),
        severity: Severity,
        message: String,
        filePath: String? = nil,
        line: Int? = nil,
        column: Int? = nil,
        code: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.message = message
        self.filePath = filePath
        self.line = line
        self.column = column
        self.code = code
    }

    /// The one-line message shown in the problems panel, combining the compiler message and its code.
    var summary: String {
        if let code {
            return "\(message) [\(code)]"
        }
        return message
    }
}
