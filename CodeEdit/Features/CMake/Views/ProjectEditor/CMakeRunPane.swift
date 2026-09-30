//
//  CMakeRunPane.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/30/26.
//

import SwiftUI

/// The executable the debugger launches, with its working directory, arguments, and environment.
struct CMakeRunPane: View {
    @Bindable var store: CMakeProjectSettingsStore

    private enum Choice: Hashable {
        case none
        case target(String)
        case custom
    }

    private var run: CMakeProjectSettings.Run { store.settings.run }

    private var choice: Binding<Choice> {
        Binding {
            if store.settings.run.customExecutable != nil { return .custom }
            if let name = store.settings.run.targetName { return .target(name) }
            return .none
        } set: { newValue in
            switch newValue {
            case .none:
                store.settings.run.targetName = nil
                store.settings.run.customExecutable = nil
            case .target(let name):
                store.settings.run.targetName = name
                store.settings.run.customExecutable = nil
            case .custom:
                // An empty path marks "custom" until one is entered; nothing launches until then.
                store.settings.run.customExecutable = store.settings.run.customExecutable ?? ""
            }
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Executable", selection: choice) {
                    Text("None").tag(Choice.none)
                    if !targetNames.isEmpty {
                        Divider()
                        ForEach(targetNames, id: \.self) { name in
                            Text(name).tag(Choice.target(name))
                        }
                    }
                    Divider()
                    Text("Custom Executable…").tag(Choice.custom)
                }
                .accessibilityIdentifier("CMakeRunTarget")
                executableDetail
            } header: {
                Text("Target")
            } footer: {
                HStack {
                    Text(LocalizedStringKey(
                        "Targets come from CMake’s codemodel after a configure, or from `add_executable()` "
                        + "calls before the first one."
                    ))
                    Spacer()
                    Button("Refresh") { store.refreshExecutableTargets() }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Launch") {
                ProjectPathField(
                    title: "Working Directory",
                    path: Binding {
                        store.settings.run.workingDirectory ?? ""
                    } set: {
                        store.settings.run.workingDirectory = $0.isEmpty ? nil : $0
                    },
                    prompt: "Project root",
                    choosesDirectories: true,
                    baseDirectory: store.sourceDirectory,
                    prefersRelativePaths: true
                )
                LabeledContent("Arguments") {
                    TextField(
                        "Arguments",
                        text: $store.settings.run.arguments,
                        prompt: Text("--flag \"value with spaces\"")
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("CMakeRunArguments")
                }
                let arguments = CommandLineArguments.split(run.arguments)
                if !arguments.isEmpty {
                    LabeledContent("Parsed") {
                        Text(arguments.map { "‹\($0)›" }.joined(separator: " "))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }

            Section {
                KeyValueListEditor(
                    rows: $store.settings.run.environment,
                    namePlaceholder: "NAME",
                    valuePlaceholder: "value",
                    emptyText: "No Environment Variables"
                )
                .accessibilityIdentifier("CMakeRunEnvironment")
            } header: {
                Text("Environment Variables")
            } footer: {
                Text("Used when you start debugging from the Debugger panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Detected targets plus the saved one, so a target missing from the current scan stays visible.
    private var targetNames: [String] {
        var names = store.executableTargets.map(\.name)
        if let saved = run.targetName, !names.contains(saved) { names.append(saved) }
        return names
    }

    @ViewBuilder private var executableDetail: some View {
        switch choice.wrappedValue {
        case .none:
            EmptyView()
        case .custom:
            ProjectPathField(
                title: "Executable Path",
                path: Binding {
                    store.settings.run.customExecutable ?? ""
                } set: {
                    store.settings.run.customExecutable = $0
                },
                prompt: "build/app",
                baseDirectory: store.sourceDirectory,
                prefersRelativePaths: true
            )
        case .target(let name):
            let artifact = store.executableTargets.first { $0.name == name }?.artifact
            LabeledContent("Binary") {
                if let artifact {
                    Text(artifact.path)
                        .textSelection(.enabled)
                        .truncationMode(.middle)
                        .foregroundStyle(FileManager.default.fileExists(atPath: artifact.path) ? .primary : .secondary)
                } else {
                    Text("Build the project to locate this target.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
