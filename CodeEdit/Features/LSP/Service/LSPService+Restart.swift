//
//  LSPService+Restart.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/14/26.
//

import Foundation

extension LSPService {
    /// The selected CMake configure preset changed, so the compilation database a running
    /// clangd was started with may be stale. Drop the cached database directory and restart
    /// the C-family servers for the workspace to pick up the new compile flags.
    /// - Parameter sourceDirectoryPath: The path of the CMake workspace whose preset changed.
    func handleConfigurePresetChange(sourceDirectoryPath: String) {
        let sourcePath = URL(fileURLWithPath: sourceDirectoryPath).standardizedFileURL.path
        Task {
            await CMakeCompilationDatabase.invalidateCache(workspacePath: sourcePath)
            let keys = languageClients.keys.filter {
                Self.clangdLanguageIds.contains($0.languageId)
                    && URL(fileURLWithPath: $0.workspacePath).standardizedFileURL.path == sourcePath
            }
            for key in keys {
                await restartServer(for: key)
            }
        }
    }

    /// Restarts a single language server, re-opening the documents it was tracking.
    /// - Parameter key: The client key identifying the server to restart.
    private func restartServer(for key: ClientKey) async {
        guard let client = languageClients[key] else { return }
        let documents = client.openFiles.documents
        stopListeningToEvents(for: key)
        do {
            try await client.shutdown()
        } catch {
            logger.error("Failed to shutdown \(key.languageId) server for restart: \(error)")
        }
        languageClients.removeValue(forKey: key)
        // The restarting server republishes diagnostics for re-opened documents; clear the
        // entries in the meantime so the problems panel never shows stale results.
        for document in documents {
            if let uri = document.languageServerURI {
                diagnosticsStore.update([], for: uri, workspacePath: key.workspacePath)
            }
        }
        do {
            let server = try await startServer(for: key.languageId, workspacePath: key.workspacePath)
            for document in documents {
                do {
                    try await server.openDocument(document)
                } catch {
                    logger.error("Failed to re-open document after restart: \(error)")
                }
            }
        } catch {
            logger.error("Failed to restart \(key.languageId) server: \(error)")
        }
    }
}
