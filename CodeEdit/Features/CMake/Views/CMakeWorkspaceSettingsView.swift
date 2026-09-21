//
//  CMakeWorkspaceSettingsView.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/11/26.
//

import SwiftUI

struct CMakeWorkspaceSettingsView: View {
    let model: CMakeWorkspace

    var body: some View {
        if let project = model.project {
            Section {
                LabeledContent("Project", value: project.name)
                if let version = project.version { LabeledContent("Version", value: version) }
                if !project.languages.isEmpty {
                    LabeledContent("Languages", value: project.languages.joined(separator: ", "))
                }
                if !project.configurePresets.isEmpty {
                    presetPickers(project)
                    presetDetails
                } else if project.errors.isEmpty {
                    Text("No available configure presets. Add presets to CMakePresets.json or CMakeUserPresets.json.")
                        .foregroundStyle(.secondary)
                }
                ForEach(project.errors, id: \.self) { error in
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    Button("Reload") { model.reload() }
                        .disabled(model.isLoading)
                        .accessibilityIdentifier("CMakeReload")
                }
            } header: {
                Text("CMake")
            } footer: {
                Text("Values come from project files. Toolchain and computed settings are resolved when CMake runs.")
            }
        } else if model.isLoading {
            Section("CMake") { ProgressView("Detecting project…") }
        }
    }

    @ViewBuilder
    private func presetPickers(_ project: CMakeProject) -> some View {
        Picker("Configure preset", selection: Binding(
            get: { model.selectedConfigurePreset }, set: { model.selectConfigurePreset($0) }
        )) {
            ForEach(project.configurePresets) { preset in Text(preset.title).tag(preset.name) }
        }
        .accessibilityIdentifier("CMakeConfigurePreset")
        if !model.availableBuildPresets.isEmpty {
            Picker("Build preset", selection: Binding(
                get: { model.selectedBuildPreset }, set: { model.selectBuildPreset($0) }
            )) {
                ForEach(model.availableBuildPresets) { preset in Text(preset.title).tag(preset.name) }
            }
            .accessibilityIdentifier("CMakeBuildPreset")
        }
    }

    @ViewBuilder private var presetDetails: some View {
        if let preset = model.configurePreset {
            detail("Generator", preset.generator ?? "CMake default")
            detail("C compiler", preset.cCompiler ?? "Resolved by CMake")
            detail("C++ compiler", preset.cxxCompiler ?? "Resolved by CMake")
            detail(preset.isMultiConfig ? "Build configuration" : "Build type", model.buildType ?? "Not specified")
            if let directory = preset.binaryDirectory { detail("Build directory", directory) }
            if let toolchain = preset.toolchainFile { detail("Toolchain", toolchain) }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
                .help(value)
        }
    }
}
