//
//  FlutterProjectPane.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import SwiftUI

/// The project editor's Flutter section: the package, the Flutter SDK, and the native CMake
/// roots with the active one selectable.
struct FlutterProjectPane: View {
    let flutterWorkspace: FlutterWorkspace

    var body: some View {
        Form {
            if let project = flutterWorkspace.project {
                Section("Project") {
                    LabeledContent("Name") { Text(project.name).textSelection(.enabled) }
                    LabeledContent("Version", value: project.pubspec.version ?? "Not Set")
                    LabeledContent("Type", value: projectType(project))
                }
            }

            Section {
                sdkRows
            } header: {
                HStack {
                    Text("Flutter SDK")
                    Spacer()
                    if flutterWorkspace.isLocatingSDK {
                        ProgressView().controlSize(.small)
                    }
                    Button("Rescan") { flutterWorkspace.locateSDK() }
                        .disabled(flutterWorkspace.isLocatingSDK)
                        .accessibilityIdentifier("FlutterRescanSDK")
                }
            } footer: {
                Text("The `flutter` command found in your login shell PATH.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                nativeRootRows
            } header: {
                Text("Native Code")
            } footer: {
                Text("The first folder with a CMakeLists.txt among the workspace root, src, cpp, native, "
                     + "linux, windows, macos and packages/*/src is active unless you pick another. "
                     + "The CMake sections and clangd use the active root's presets and compilation database.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("ProjectEditorFlutter")
    }

    @ViewBuilder private var sdkRows: some View {
        if let sdk = flutterWorkspace.sdk {
            LabeledContent("Path") {
                Text(sdk.rootDirectory.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(sdk.rootDirectory.path)
            }
            LabeledContent("Version", value: sdkVersion(sdk))
        } else if flutterWorkspace.isLocatingSDK || !flutterWorkspace.hasLocatedSDK {
            LabeledContent("Path") { Text("Detecting…").foregroundStyle(.secondary) }
        } else {
            LabeledContent("Path") {
                Label(
                    "Flutter was not found. Add the SDK's bin folder to your login shell PATH.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder private var nativeRootRows: some View {
        let roots = flutterWorkspace.nativeRoots
        if roots.isEmpty {
            Text("No CMakeLists.txt was found in the native code folders.")
                .foregroundStyle(.secondary)
        } else {
            Picker("Active Root", selection: Binding(
                get: { flutterWorkspace.activeNativeRoot },
                set: { root in
                    if let root { flutterWorkspace.selectNativeRoot(root) }
                }
            )) {
                ForEach(roots, id: \.self) { root in
                    Text(flutterWorkspace.displayName(of: root))
                        .help(root.path)
                        .tag(URL?.some(root))
                }
            }
            .pickerStyle(.radioGroup)
            .accessibilityIdentifier("FlutterNativeRoot")
        }
    }

    private func projectType(_ project: FlutterProject) -> String {
        guard project.isFFIPlugin else { return "App or Package" }
        return "FFI Plugin (\(project.pubspec.ffiPluginPlatforms.joined(separator: ", ")))"
    }

    private func sdkVersion(_ sdk: FlutterSDK) -> String {
        var parts = [sdk.version ?? "Unknown"]
        if let channel = sdk.channel { parts.append(channel) }
        if let dart = sdk.dartVersion { parts.append("Dart \(dart)") }
        return parts.joined(separator: " · ")
    }
}
