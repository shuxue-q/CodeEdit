//
//  CMakeToolchainPane.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/30/26.
//

import SwiftUI

/// Compilers, the CMake executable, and the generator.
struct CMakeToolchainPane: View {
    @Bindable var store: CMakeProjectSettingsStore

    private var presetIsActive: Bool { store.activeConfigurePreset != nil }

    var body: some View {
        Form {
            PresetOverrideNotice(preset: store.activeConfigurePreset)

            Section {
                CompilerPicker(
                    title: "C Compiler",
                    path: $store.settings.toolchain.cCompiler,
                    detected: store.toolchain?.cCompilers ?? [],
                    baseDirectory: store.sourceDirectory
                )
                .accessibilityIdentifier("CMakeCCompiler")
                CompilerPicker(
                    title: "C++ Compiler",
                    path: $store.settings.toolchain.cxxCompiler,
                    detected: store.toolchain?.cxxCompilers ?? [],
                    baseDirectory: store.sourceDirectory
                )
                .accessibilityIdentifier("CMakeCXXCompiler")
            } header: {
                Text("Compilers")
            } footer: {
                Text("Found in your login shell PATH and "
                     + CMakeToolchainDetector.standardDirectories.joined(separator: ", ") + ". "
                     + "Changing a compiler starts a fresh configure on the next build.")
            }
            .disabled(presetIsActive)

            Section {
                cmakeRows
                Picker("Generator", selection: $store.settings.toolchain.generator) {
                    Text("CMake Default").tag(String?.none)
                    Divider()
                    ForEach(CMakeGenerator.allCases) { generator in
                        Text(generatorTitle(generator)).tag(String?.some(generator.rawValue))
                    }
                    if let custom = store.settings.toolchain.generator,
                       CMakeGenerator(rawValue: custom) == nil {
                        Text(custom).tag(String?.some(custom))
                    }
                }
                .disabled(presetIsActive)
                .accessibilityIdentifier("CMakeGenerator")
            } header: {
                Text("CMake")
            } footer: {
                HStack {
                    Spacer()
                    if store.isScanningToolchain {
                        ProgressView().controlSize(.small)
                    }
                    Button("Rescan Toolchain") { store.scanToolchain(force: true) }
                        .disabled(store.isScanningToolchain)
                        .accessibilityIdentifier("CMakeRescanToolchain")
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var cmakeRows: some View {
        if let cmake = store.toolchain?.cmake {
            LabeledContent("Executable") {
                Text(cmake.path).textSelection(.enabled)
            }
            LabeledContent("Version", value: cmake.version ?? "Unknown")
        } else if store.isScanningToolchain || store.toolchain == nil {
            LabeledContent("Executable") { Text("Detecting…").foregroundStyle(.secondary) }
        } else {
            LabeledContent("Executable") {
                Label(
                    "CMake was not found. Install it with Homebrew (`brew install cmake`).",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            }
        }
    }

    private func generatorTitle(_ generator: CMakeGenerator) -> String {
        guard let toolchain = store.toolchain, !toolchain.availableGenerators.contains(generator) else {
            return generator.rawValue
        }
        return "\(generator.rawValue) (\(generator.buildTool) not found)"
    }
}

/// Picks a detected compiler, CMake's default, or a custom path.
private struct CompilerPicker: View {
    private enum Choice: Hashable {
        case automatic
        case detected(String)
        case custom
    }

    let title: String
    @Binding var path: String?
    let detected: [DetectedCompiler]
    let baseDirectory: URL

    private var choice: Binding<Choice> {
        Binding {
            guard let path else { return .automatic }
            return detected.contains { $0.path == path } ? .detected(path) : .custom
        } set: { newValue in
            switch newValue {
            case .automatic: path = nil
            case .detected(let detectedPath): path = detectedPath
            // An empty path marks "custom" until one is entered; it is never passed to CMake.
            case .custom: if path == nil || detected.contains(where: { $0.path == path }) { path = "" }
            }
        }
    }

    var body: some View {
        Picker(title, selection: choice) {
            Text("CMake Default").tag(Choice.automatic)
            if !detected.isEmpty {
                Divider()
                ForEach(detected) { compiler in
                    Text("\(compiler.title) — \(compiler.path)").tag(Choice.detected(compiler.path))
                }
            }
            Divider()
            Text("Custom Path…").tag(Choice.custom)
        }
        if choice.wrappedValue == .custom {
            ProjectPathField(
                title: "\(title) Path",
                path: Binding { path ?? "" } set: { path = $0 },
                prompt: "/path/to/compiler",
                baseDirectory: baseDirectory
            )
            if let path, !path.isEmpty, !FileManager.default.isExecutableFile(atPath: path) {
                Label("No executable at this path.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
    }
}
