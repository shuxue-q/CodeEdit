//
//  LSPDiagnosticsStore.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/14/26.
//

import Foundation
import Observation
import LanguageServerProtocol

/// Collects `textDocument/publishDiagnostics` notifications from running language servers,
/// keyed by workspace path and document URI.
///
/// This is the problems panel's language-server data source. Servers republish a document's
/// full diagnostic set on every change, so the store only keeps the latest set per document;
/// an empty set clears the entry.
@MainActor
@Observable
final class LSPDiagnosticsStore {
    /// Diagnostics per workspace path, keyed by document URI.
    private(set) var diagnostics: [String: [String: [Diagnostic]]] = [:]

    /// Replaces the diagnostics published for a document. An empty array removes the entry.
    /// - Parameters:
    ///   - newDiagnostics: The document's complete new diagnostic set.
    ///   - uri: The document's LSP URI.
    ///   - workspacePath: The workspace the publishing server is rooted at.
    func update(_ newDiagnostics: [Diagnostic], for uri: DocumentUri, workspacePath: String) {
        var workspace = diagnostics[workspacePath] ?? [:]
        workspace[uri] = newDiagnostics.isEmpty ? nil : newDiagnostics
        diagnostics[workspacePath] = workspace.isEmpty ? nil : workspace
    }

    /// All diagnostics for a workspace, keyed by document URI.
    /// - Parameter workspacePath: The workspace path to look up.
    /// - Returns: The workspace's diagnostics, or an empty dictionary when none were published.
    func diagnostics(for workspacePath: String) -> [String: [Diagnostic]] {
        diagnostics[workspacePath] ?? [:]
    }

    /// Drops all diagnostics belonging to a closed workspace.
    /// - Parameter workspacePath: The workspace path to remove.
    func removeWorkspace(_ workspacePath: String) {
        diagnostics[workspacePath] = nil
    }
}

extension CMakeBuildDiagnostic {
    /// Creates a problems-panel entry from a language server diagnostic.
    ///
    /// LSP positions are zero-based; the panel displays one-based line and column numbers.
    /// The diagnostic's source (for example `clangd`) is shown as the entry's code.
    /// - Parameters:
    ///   - lspDiagnostic: The diagnostic published by the server.
    ///   - uri: The URI of the document the diagnostic belongs to.
    init?(lspDiagnostic: Diagnostic, uri: DocumentUri) {
        guard let url = URL(string: uri) else { return nil }
        let severity: Severity
        switch lspDiagnostic.severity {
        case .error: severity = .error
        case .warning: severity = .warning
        case .information, .hint, nil: severity = .note
        }
        var code = lspDiagnostic.source
        if let lspCode = lspDiagnostic.code {
            switch lspCode {
            case .optionA(let value): code = String(value)
            case .optionB(let value): code = value
            }
        }
        self.init(
            severity: severity,
            message: lspDiagnostic.message,
            filePath: url.path(percentEncoded: false),
            line: lspDiagnostic.range.start.line + 1,
            column: lspDiagnostic.range.start.character + 1,
            code: code
        )
    }
}
