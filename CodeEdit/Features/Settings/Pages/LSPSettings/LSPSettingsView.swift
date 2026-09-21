//
//  LSPSettingsView.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/11/26.
//

import SwiftUI

/// A view that implements the Language Servers settings section
struct LSPSettingsView: View {
    @StateObject private var model = LSPSettingsViewModel()

    @AppSettings(\.lsp.servers)
    var configuredServers

    var body: some View {
        SettingsForm {
            Section {
                ForEach(LanguageServerDetector.supportedServers, id: \.executable) { server in
                    serverRow(server)
                }
            } header: {
                Text("Language Servers")
                Text(
                    "CodeEdit does not install language servers itself. " +
                    "Servers installed on your system are detected automatically " +
                    "and provide completion, hover, and more."
                )
            } footer: {
                HStack {
                    if model.isDetecting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("Detect Servers") {
                        model.detect()
                    }
                    .disabled(model.isDetecting)
                }
            }
        }
        .onAppear {
            model.detectIfNeeded()
        }
    }

    @ViewBuilder
    private func serverRow(_ server: LanguageServerDetector.SupportedServer) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(server.executable)
                Text(server.languageIds.joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let status = status(for: server) {
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(status)
            } else {
                Text("Not Found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if isConfigured(server) {
                Button("Reset") {
                    model.resetServer(server)
                }
            }
            Button("Choose…") {
                model.chooseBinary(for: server)
            }
        }
    }

    /// The path of the binary used for a supported server: manually configured,
    /// auto-detected, or `nil` when no server was found.
    private func status(for server: LanguageServerDetector.SupportedServer) -> String? {
        let languageIds = server.languageIds
        if let configured = languageIds.lazy.compactMap({ configuredServers[$0] }).first {
            return configured.path
        }
        return languageIds.lazy.compactMap { model.detectedServers[$0] }.first?.execPath
    }

    /// Whether the user picked a binary manually for the given server.
    private func isConfigured(_ server: LanguageServerDetector.SupportedServer) -> Bool {
        server.languageIds.contains { configuredServers[$0] != nil }
    }
}
