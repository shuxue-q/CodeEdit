//
//  DeveloperSettingsView.swift
//  CodeEdit
//
//  Created by Abe Malla on 5/16/24.
//

import SwiftUI
import LanguageServerProtocol

/// A view that implements the Developer settings section
struct DeveloperSettingsView: View {
    @AppSettings(\.developerSettings.lspBinaries)
    var lspBinaries

    @AppSettings(\.developerSettings.showInternalDevelopmentInspector)
    var showInternalDevelopmentInspector

    /// All valid LSP language identifiers, including auto-detected servers outside
    /// of `LanguageIdentifier` (e.g. CMake).
    private var validLanguageIds: [String] {
        var seen = Set<String>()
        return (LanguageIdentifier.allCases.map(\.rawValue) + LanguageServerDetector.supportedLanguageIds)
            .filter { seen.insert($0).inserted }
    }

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Show Internal Development Inspector", isOn: $showInternalDevelopmentInspector)
            }

            Section {
                KeyValueTable(
                    items: $lspBinaries,
                    validKeys: validLanguageIds,
                    keyColumnName: "Language",
                    valueColumnName: "Language Server Path",
                    newItemInstruction: "Add a language server"
                ) {
                    Text("Add a language server")
                    Text(
                        "Specify the absolute path to your LSP binary and its associated language."
                    )
                } actionBarTrailing: {
                    EmptyView()
                }
                .frame(minHeight: 96)
            } header: {
                Text("LSP Binaries")
                Text("Specify the language and the absolute path to the language server binary.")
            }
        }
    }
}
