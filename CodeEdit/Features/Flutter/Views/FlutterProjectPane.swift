//
//  FlutterProjectPane.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import SwiftUI

/// The project editor's Flutter section: the package and its configuration files, the Flutter
/// SDK, dependencies, platforms, the native CMake roots, and the run settings.
struct FlutterProjectPane: View {
    let flutterWorkspace: FlutterWorkspace
    let inventory: ProjectInventory?
    /// Runs a generated task, such as `flutter pub get`.
    let runTask: (ProjectToolchain, GeneratedTaskInfo.Role) -> Void

    var body: some View {
        Form {
            if let project = flutterWorkspace.project {
                projectSection(project)
            }
            sdkSection
            if let project = flutterWorkspace.project {
                packagesSection(project)
                platformsSection(project)
                analysisSection(project)
            }
            nativeCodeSection
            FlutterRunSettingsSection(flutterWorkspace: flutterWorkspace, settings: flutterWorkspace.settings)
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("ProjectEditorFlutter")
    }

    // MARK: - Project

    @ViewBuilder
    private func projectSection(_ project: FlutterProject) -> some View {
        Section("Project") {
            LabeledContent("Name") { Text(project.name).textSelection(.enabled) }
            LabeledContent("Version", value: project.pubspec.version ?? String(localized: "Not Set"))
            LabeledContent("Type", value: projectType(project))
            if let description = project.pubspec.description {
                LabeledContent("Description") {
                    Text(description).multilineTextAlignment(.trailing).textSelection(.enabled)
                }
            }
            if project.pubspec.sdkConstraint != nil || project.pubspec.flutterConstraint != nil {
                LabeledContent("SDK Constraints", value: constraints(project.pubspec))
            }
            if let publishTo = project.pubspec.publishTo {
                LabeledContent("Publish To", value: publishTo)
            }
        }
    }

    private func projectType(_ project: FlutterProject) -> String {
        guard project.isFFIPlugin else { return project.typeTitle }
        let platforms = project.pubspec.ffiPluginPlatforms.joined(separator: ", ")
        return String(localized: "FFI Plugin (\(platforms))")
    }

    private func constraints(_ pubspec: Pubspec) -> String {
        [pubspec.sdkConstraint.map { "Dart \($0)" }, pubspec.flutterConstraint.map { "Flutter \($0)" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    // MARK: - SDK

    private var sdkSection: some View {
        Section {
            sdkRows
            FlutterSDKOverrideField(flutterWorkspace: flutterWorkspace)
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
            Text(LocalizedStringKey(
                "The `flutter` command found in your login shell PATH, unless an SDK folder is chosen for this "
                + "workspace. The choice is kept on this Mac only and also selects the Dart analysis server."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
                    flutterWorkspace.sdkOverride == nil
                        ? "Flutter was not found. Add the SDK's bin folder to your login shell PATH."
                        : "The chosen folder is not a Flutter SDK.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            }
        }
    }

    private func sdkVersion(_ sdk: FlutterSDK) -> String {
        var parts = [sdk.version ?? String(localized: "Unknown")]
        if let channel = sdk.channel { parts.append(channel) }
        if let dart = sdk.dartVersion { parts.append("Dart \(dart)") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Native code

    private var nativeCodeSection: some View {
        Section {
            nativeRootRows
            if let hook = flutterWorkspace.project?.nativeAssetsHook {
                LabeledContent("Build Hook") {
                    Text(hookSummary(hook))
                }
            }
        } header: {
            Text("Native Code")
        } footer: {
            Text(LocalizedStringKey(
                "The first folder with a CMakeLists.txt among the workspace root, src, cpp, native, "
                + "linux, windows, macos and packages/*/src is active unless you pick another. "
                + "The C++ section and clangd use the active root's presets and compilation database."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func hookSummary(_ hook: NativeAssetsHook) -> String {
        let tools = [hook.runsCMake ? "CMake" : nil, hook.runsCargo ? "Cargo" : nil].compactMap { $0 }
        guard !tools.isEmpty else { return NativeAssetsHook.relativePath }
        let toolList = tools.count == 2
            ? String(localized: "\(tools[0]) and \(tools[1])")
            : tools.joined(separator: " and ")
        return String(localized: "\(NativeAssetsHook.relativePath), runs \(toolList)")
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
}

// MARK: - Packages and analysis

extension FlutterProjectPane {
    @ViewBuilder
    private func packagesSection(_ project: FlutterProject) -> some View {
        Section {
            LabeledContent("Resolution") {
                HStack {
                    pubStateLabel(project.pubState)
                    Button("Pub Get") { runTask(.flutter, .dependencies) }
                        .accessibilityIdentifier("FlutterPubGet")
                }
            }
            let pubspec = project.pubspec
            LabeledContent("Dependencies", value: dependencyCounts(pubspec))
            let local = pubspec.dependencies.filter {
                if case .path = $0.source { return true }
                if case .git = $0.source { return true }
                return false
            }
            if !local.isEmpty {
                LabeledContent("Local and Git") {
                    Text(local.map { "\($0.name) (\($0.sourceDescription))" }.joined(separator: "\n"))
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
            }
            DisclosureGroup("All Dependencies") {
                ForEach(PubDependency.Kind.allCases, id: \.self) { kind in
                    let dependencies = pubspec.dependencies(of: kind)
                    if !dependencies.isEmpty {
                        Text(kind.rawValue).font(.caption).foregroundStyle(.secondary)
                        ForEach(dependencies) { dependency in
                            LabeledContent(dependency.name, value: dependency.sourceDescription)
                        }
                    }
                }
            }
            if !pubspec.assets.isEmpty || !pubspec.fontFamilies.isEmpty {
                LabeledContent("Assets", value: String(localized: "\(pubspec.assets.count) paths"))
                if !pubspec.fontFamilies.isEmpty {
                    LabeledContent("Fonts", value: pubspec.fontFamilies.joined(separator: ", "))
                }
            }
        } header: {
            Text("Packages")
        }
    }

    @ViewBuilder
    private func pubStateLabel(_ state: PubResolutionState) -> some View {
        switch state {
        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle").foregroundStyle(.green)
        case .outdated:
            Label("Outdated", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .help("pubspec.yaml or pubspec.lock changed since the last pub get")
        case .missing:
            Label("Not resolved yet", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
    }

    private func dependencyCounts(_ pubspec: Pubspec) -> String {
        let normal = pubspec.dependencies(of: .normal).count
        let dev = pubspec.dependencies(of: .development).count
        let overrides = pubspec.dependencies(of: .override).count
        if overrides > 0 {
            return String(localized: "\(normal) · \(dev) dev · \(overrides) overrides")
        }
        return String(localized: "\(normal) · \(dev) dev")
    }

    // MARK: - Platforms and analysis

    @ViewBuilder
    private func platformsSection(_ project: FlutterProject) -> some View {
        Section("Platforms") {
            HStack(spacing: 14) {
                ForEach(FlutterPlatform.allCases) { platform in
                    let present = project.platforms.contains(platform)
                    Label(platform.title, systemImage: present ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(present ? Color.primary : Color.secondary)
                }
            }
            if !project.pubspec.pluginPlatforms.isEmpty {
                LabeledContent("Plugin Platforms") {
                    Text(project.pubspec.pluginPlatforms.map { platform in
                        platform.isFFIPlugin ? "\(platform.name) (FFI)" : platform.name
                    }.joined(separator: ", "))
                }
            }
        }
    }

    @ViewBuilder
    private func analysisSection(_ project: FlutterProject) -> some View {
        Section("Analysis") {
            if let options = project.analysisOptions {
                if !options.includes.isEmpty {
                    LabeledContent("Includes", value: options.includes.joined(separator: ", "))
                }
                let count = options.excludes.count
                let excluded = switch count {
                case 0: String(localized: "None")
                case 1: String(localized: "1 pattern")
                default: String(localized: "\(count) patterns")
                }
                LabeledContent("Excluded", value: excluded)
                    .help(options.excludes.joined(separator: "\n"))
                if !options.strictModes.isEmpty {
                    LabeledContent("Strict Modes", value: options.strictModes.joined(separator: ", "))
                }
                if !options.enabledRules.isEmpty || !options.disabledRules.isEmpty {
                    let enabled = options.enabledRules.count
                    let disabled = options.disabledRules.count
                    LabeledContent("Lint Rules", value: String(localized: "\(enabled) on · \(disabled) off"))
                }
                if !options.severityOverrides.isEmpty {
                    LabeledContent("Severity Overrides", value: "\(options.severityOverrides.count)")
                }
            } else {
                Text("No analysis_options.yaml; the analyzer uses its defaults.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
