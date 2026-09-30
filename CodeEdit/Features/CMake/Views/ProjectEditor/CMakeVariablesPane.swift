//
//  CMakeVariablesPane.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/30/26.
//

import SwiftUI

/// Extra `-D` cache definitions and a preview of the resulting configure command.
struct CMakeVariablesPane: View {
    @Bindable var store: CMakeProjectSettingsStore

    var body: some View {
        Form {
            Section {
                KeyValueListEditor(
                    rows: $store.settings.variables,
                    namePlaceholder: "NAME or NAME:TYPE",
                    valuePlaceholder: "ON",
                    emptyText: "No CMake Variables",
                    splitsDefinitions: true
                )
                .accessibilityIdentifier("CMakeVariables")
            } header: {
                Text("Cache Definitions")
            } footer: {
                Text(LocalizedStringKey(
                    "Each enabled row is passed as `-DNAME=VALUE` after the toolchain settings, so it "
                    + "wins over them and over preset cache variables. Entering `-DNAME=VALUE` as a name "
                    + "fills both columns."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Configure Command") {
                Text(commandPreview)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("CMakeConfigureCommand")
            }
        }
        .formStyle(.grouped)
    }

    /// The configure invocation, quoted for display where an argument contains spaces.
    private var commandPreview: String {
        let arguments = store.configureOptions.configureArguments.map { argument in
            argument.contains(where: { $0.isWhitespace || $0 == "\"" })
                ? "\"" + argument.replacingOccurrences(of: "\"", with: "\\\"") + "\""
                : argument
        }
        return (["cmake"] + arguments).joined(separator: " ")
    }
}
