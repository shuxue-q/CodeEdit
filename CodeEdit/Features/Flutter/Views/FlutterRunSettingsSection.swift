//
//  FlutterRunSettingsSection.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import SwiftUI

/// Chooses a Flutter SDK folder for this workspace instead of the one on `PATH`.
struct FlutterSDKOverrideField: View {
    let flutterWorkspace: FlutterWorkspace
    @State private var path = ""

    var body: some View {
        LabeledContent("SDK Folder") {
            HStack(spacing: 6) {
                TextField("SDK Folder", text: $path, prompt: Text("Use flutter on PATH"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { flutterWorkspace.setSDKOverride(path) }
                Button("Choose…", action: choose)
                if flutterWorkspace.sdkOverride != nil {
                    Button("Clear") {
                        path = ""
                        flutterWorkspace.setSDKOverride(nil)
                    }
                }
            }
        }
        .onAppear { path = flutterWorkspace.sdkOverride ?? "" }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose a Flutter SDK folder (the one containing bin/flutter)")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = url.path
        flutterWorkspace.setSDKOverride(path)
    }
}

/// The Flutter run settings: device, build mode, entry point, flavor, defines and arguments.
struct FlutterRunSettingsSection: View {
    let flutterWorkspace: FlutterWorkspace
    @Bindable var settings: ProjectSettingsFile<FlutterProjectSettings>

    var body: some View {
        Section {
            LabeledContent("Device") {
                HStack(spacing: 6) {
                    Picker("Device", selection: deviceBinding) {
                        ForEach(deviceChoices) { device in
                            Text(deviceTitle(device)).tag(device.id)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    if flutterWorkspace.isListingDevices {
                        ProgressView().controlSize(.small)
                    }
                    Button {
                        flutterWorkspace.refreshDevices()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("List connected devices")
                    .disabled(flutterWorkspace.isListingDevices)
                }
            }
            Picker("Build Mode", selection: $settings.value.buildMode) {
                ForEach(FlutterBuildMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            TextField("Target", text: optionalText(\.target), prompt: Text("lib/main.dart"))
            TextField("Flavor", text: optionalText(\.flavor), prompt: Text("None"))
            TextField("Extra Arguments", text: $settings.value.runArguments, prompt: Text("--verbose"))
            Toggle("Hot reload on save", isOn: $settings.value.hotReloadOnSave)
            VStack(alignment: .leading, spacing: 6) {
                Text("Dart Defines")
                KeyValueListEditor(rows: $settings.value.dartDefines, emptyText: "No --dart-define values")
                    .frame(minHeight: 110)
            }
        } header: {
            Text("Run")
        } footer: {
            Text("""
                Used by the generated Run and Build tasks. Hot reload works in debug mode. \
                Saved in .codeedit/\(FlutterProjectSettings.fileName).
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task {
            if !flutterWorkspace.hasListedDevices && !flutterWorkspace.isListingDevices {
                flutterWorkspace.refreshDevices()
            }
        }
    }

    private var deviceChoices: [FlutterDevice] {
        var devices = flutterWorkspace.devices
        if !devices.contains(where: { $0.id == FlutterDevice.macOS.id }) {
            devices.insert(.macOS, at: 0)
        }
        let selected = flutterWorkspace.selectedDevice
        if !devices.contains(where: { $0.id == selected.id }) {
            devices.append(selected)
        }
        return devices
    }

    private func deviceTitle(_ device: FlutterDevice) -> String {
        guard let sdk = device.sdk else { return device.name }
        return "\(device.name) (\(sdk))"
    }

    private var deviceBinding: Binding<String> {
        Binding(
            get: { settings.value.device ?? FlutterDevice.macOS.id },
            set: { settings.value.device = $0 == FlutterDevice.macOS.id ? nil : $0 }
        )
    }

    private func optionalText(_ keyPath: WritableKeyPath<FlutterProjectSettings, String?>) -> Binding<String> {
        Binding(
            get: { settings.value[keyPath: keyPath] ?? "" },
            set: { settings.value[keyPath: keyPath] = $0.trimmedNonEmpty }
        )
    }
}
