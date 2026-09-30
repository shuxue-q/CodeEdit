//
//  CMakeBuildSettingsPane.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/30/26.
//

import SwiftUI

/// Presets, build configuration, build directory, and C++ standard.
struct CMakeBuildSettingsPane: View {
    @Bindable var store: CMakeProjectSettingsStore
    let cmakeWorkspace: CMakeWorkspace

    private var presetIsActive: Bool { store.activeConfigurePreset != nil }

    var body: some View {
        Form {
            if let project = cmakeWorkspace.project,
               !project.configurePresets.isEmpty || !project.errors.isEmpty {
                CMakeWorkspaceSettingsView(model: cmakeWorkspace)
            }

            PresetOverrideNotice(preset: store.activeConfigurePreset)

            Section {
                Picker("Build Configuration", selection: $store.settings.build.configuration) {
                    ForEach(CMakeBuildConfiguration.allCases) { configuration in
                        Text(configuration.rawValue).tag(configuration)
                    }
                }
                .accessibilityIdentifier("CMakeBuildConfiguration")

                ProjectPathField(
                    title: "Build Directory",
                    path: $store.settings.build.buildDirectory,
                    prompt: CMakeProjectSettings.Build.defaultBuildDirectory,
                    choosesDirectories: true,
                    baseDirectory: store.sourceDirectory,
                    prefersRelativePaths: true
                )
                .accessibilityIdentifier("CMakeBuildDirectory")

                Picker("C++ Standard", selection: $store.settings.build.cxxStandard) {
                    Text("Project Default").tag(CMakeCXXStandard?.none)
                    ForEach(CMakeCXXStandard.allCases) { standard in
                        Text(standard.title).tag(CMakeCXXStandard?.some(standard))
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("CMakeCXXStandard")
            } header: {
                Text("Configuration")
            } footer: {
                footer
            }
            .disabled(presetIsActive)
        }
        .formStyle(.grouped)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Resolved build directory") {
                Text(store.configureOptions.buildDirectory.path)
                    .textSelection(.enabled)
                    .truncationMode(.middle)
            }
            if CMakeGenerator.isMultiConfig(store.settings.toolchain.generator) {
                Text("Multi-configuration generators build the selected configuration with `--config`.")
            }
            Text("“Project Default” leaves `CMAKE_CXX_STANDARD` to the project’s own CMakeLists.txt.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
