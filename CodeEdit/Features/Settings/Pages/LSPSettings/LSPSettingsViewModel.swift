//
//  LSPSettingsViewModel.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/11/26.
//

import AppKit
import Foundation

/// The view model backing ``LSPSettingsView``.
///
/// Runs language server detection through ``LSPService`` and persists the user's
/// manually picked binaries in the settings.
@MainActor
final class LSPSettingsViewModel: ObservableObject {
    /// Whether a detection pass is currently running.
    @Published private(set) var isDetecting = false
    /// The binaries found by the most recent detection pass, keyed by LSP language identifier.
    @Published private(set) var detectedServers: [String: LanguageServerBinary] = [:]

    /// Whether detection has run at least once since the view model was created.
    private var didDetect = false

    @Service private var lspService: LSPService

    /// Runs detection once, when the settings page first appears.
    func detectIfNeeded() {
        guard !didDetect else { return }
        detect()
    }

    /// Searches the login shell `PATH` for supported language servers.
    func detect() {
        guard !isDetecting else { return }
        isDetecting = true
        didDetect = true
        Task {
            detectedServers = await lspService.redetectServers()
            isDetecting = false
        }
    }

    /// Asks the user to pick the server's executable and stores it in the settings.
    /// - Parameter server: The supported server to configure.
    func chooseBinary(for server: LanguageServerDetector.SupportedServer) {
        let openPanel = NSOpenPanel()
        openPanel.prompt = "Choose"
        openPanel.message = "Choose the \(server.executable) executable"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.treatsFilePackagesAsDirectories = false

        openPanel.begin { result in
            guard result == .OK, let url = openPanel.url else { return }
            var servers = Settings[\.lsp.servers]
            for languageId in server.languageIds {
                servers[languageId] = .init(path: url.path, arguments: server.arguments)
            }
            Settings[\.lsp.servers] = servers
        }
    }

    /// Removes the manually picked binary for the given server, reverting to auto-detection.
    /// - Parameter server: The supported server to reset.
    func resetServer(_ server: LanguageServerDetector.SupportedServer) {
        var servers = Settings[\.lsp.servers]
        for languageId in server.languageIds {
            servers.removeValue(forKey: languageId)
        }
        Settings[\.lsp.servers] = servers
        detect()
    }
}
