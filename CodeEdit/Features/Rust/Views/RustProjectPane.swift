//
//  RustProjectPane.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import SwiftUI

/// The project editor's Rust section: the Cargo workspace and its packages, the pinned toolchain
/// and what is installed, and the build and run settings of the generated Cargo tasks.
struct RustProjectPane: View {
    let model: ProjectInventoryModel
    @Bindable var state: ProjectEditorState
    /// Runs a generated task.
    let runTask: (ProjectToolchain, GeneratedTaskInfo.Role) -> Void

    private var roots: [CargoRoot] { model.inventory?.cargoRoots ?? [] }

    private var root: CargoRoot? {
        roots.first { $0.directory.path == state.selectedCargoRoot } ?? roots.first
    }

    var body: some View {
        Form {
            if roots.count > 1 {
                Section {
                    Picker("Cargo Root", selection: Binding(
                        get: { root?.directory.path ?? "" },
                        set: { state.selectedCargoRoot = $0 }
                    )) {
                        ForEach(roots) { root in
                            Text(relativePath(root)).tag(root.directory.path)
                        }
                    }
                }
            }
            if let root {
                manifestSection(root)
                packagesSection(root)
                RustToolchainSection(root: root, status: model.rustStatus(for: root), model: model)
                CargoSettingsSections(root: root, path: relativePath(root), settings: model.cargoSettings)
            } else {
                Text("No Cargo.toml was found in the workspace.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("ProjectEditorRust")
    }

    private func relativePath(_ root: CargoRoot) -> String {
        model.inventory?.relativePath(of: root.directory) ?? root.directory.lastPathComponent
    }

    private func manifestPath(_ root: CargoRoot) -> String {
        let folder = relativePath(root)
        return folder == "." ? CargoManifest.fileName : "\(folder)/\(CargoManifest.fileName)"
    }

    private func versionLabel(_ manifest: CargoManifest) -> String {
        manifest.version ?? (manifest.inheritedKeys.contains("version") ? "workspace" : "")
    }

    // MARK: - Manifest

    @ViewBuilder
    private func manifestSection(_ root: CargoRoot) -> some View {
        Section {
            LabeledContent("Manifest") {
                Text(manifestPath(root))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            if root.isWorkspace {
                LabeledContent("Members", value: root.packages.map(\.name).joined(separator: ", "))
                if let resolver = root.manifest.resolver {
                    LabeledContent("Resolver", value: resolver)
                }
                if !root.manifest.workspaceExclude.isEmpty {
                    LabeledContent("Excluded", value: root.manifest.workspaceExclude.joined(separator: ", "))
                }
            }
            if !root.manifest.parseErrors.isEmpty {
                ForEach(Array(root.manifest.parseErrors.enumerated()), id: \.offset) { _, error in
                    Label("Line \(error.line): \(error.message)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            HStack {
                Text(root.isWorkspace ? "Cargo Workspace" : "Cargo Package")
                Spacer()
                Button("Check") { runTask(.cargo, .check) }
                Button("Build") { runTask(.cargo, .build) }
                    .accessibilityIdentifier("CargoBuild")
            }
        }
    }

    // MARK: - Packages

    @ViewBuilder
    private func packagesSection(_ root: CargoRoot) -> some View {
        Section("Packages") {
            ForEach(root.packages) { package in
                DisclosureGroup {
                    packageDetails(package)
                } label: {
                    HStack {
                        Text(package.name).fontWeight(.medium)
                        Text(versionLabel(package.manifest))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(targetSummary(package))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func packageDetails(_ package: CargoPackage) -> some View {
        let manifest = package.manifest
        if let edition = manifest.edition {
            LabeledContent("Edition", value: edition)
        }
        if let rustVersion = manifest.rustVersion {
            LabeledContent("Minimum Rust", value: rustVersion)
        }
        if let description = manifest.description {
            LabeledContent("Description") {
                Text(description).multilineTextAlignment(.trailing)
            }
        }
        ForEach(CargoTarget.Kind.allCases, id: \.self) { kind in
            let targets = package.targets(of: kind)
            if !targets.isEmpty {
                LabeledContent(kind.title) {
                    Text(targets.map(targetLabel).joined(separator: "\n"))
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
            }
        }
        if !manifest.features.isEmpty {
            LabeledContent("Features") {
                Text(manifest.features.map { feature in
                    let enables = feature.enables.joined(separator: ", ")
                    return feature.enables.isEmpty ? feature.name : "\(feature.name) → \(enables)"
                }.joined(separator: "\n"))
                .multilineTextAlignment(.trailing)
            }
        }
        ForEach(CargoDependency.Kind.allCases, id: \.self) { kind in
            let dependencies = manifest.dependencies.filter { $0.kind == kind }
            if !dependencies.isEmpty {
                LabeledContent(kind.rawValue) {
                    Text(dependencies.map { dependency in
                        var text = "\(dependency.name) \(dependency.sourceDescription)"
                        if dependency.isOptional { text += String(localized: " (optional)") }
                        if let platform = dependency.platform { text += " [\(platform)]" }
                        return text
                    }.joined(separator: "\n"))
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                }
            }
        }
    }

    private func targetLabel(_ target: CargoTarget) -> String {
        var label = target.name ?? target.path ?? ""
        if !target.crateTypes.isEmpty && target.crateTypes != ["lib"] {
            label += " (\(target.crateTypes.joined(separator: ", ")))"
        }
        return label
    }

    private func targetSummary(_ package: CargoPackage) -> String {
        CargoTarget.Kind.allCases.compactMap { kind in
            let targets = package.targets(of: kind)
            guard !targets.isEmpty else { return nil }
            let count = targets.count
            let name = kind.title.lowercased()
            return count == 1 ? name : String(localized: "\(count) \(name)s")
        }.joined(separator: " · ")
    }
}

/// The pinned toolchain and what rustup has installed for it.
private struct RustToolchainSection: View {
    let root: CargoRoot
    let status: RustToolchainStatus?
    let model: ProjectInventoryModel

    var body: some View {
        Section {
            if let file = root.toolchainFile {
                LabeledContent("Pinned By", value: file.url.lastPathComponent)
                    .help(file.url.path)
                LabeledContent("Channel", value: file.channel ?? file.path ?? String(localized: "Not set"))
                if !file.targets.isEmpty {
                    LabeledContent("Targets") {
                        VStack(alignment: .trailing, spacing: 2) {
                            ForEach(file.targets, id: \.self) { target in
                                installedLabel(target, installed: status?.hasTarget(target))
                            }
                        }
                    }
                }
                if !file.components.isEmpty {
                    LabeledContent("Components") {
                        VStack(alignment: .trailing, spacing: 2) {
                            ForEach(file.components, id: \.self) { component in
                                installedLabel(component, installed: status?.hasComponent(component))
                            }
                        }
                    }
                }
            } else {
                LabeledContent("Pinned By", value: String(localized: "Nothing (rustup default)"))
            }
            LabeledContent("Active Toolchain") {
                activeToolchain
            }
            LabeledContent("Standard Library Source") {
                installedLabel("rust-src", installed: status?.hasComponent("rust-src"))
            }
            .help("rust-analyzer needs rust-src to complete std items.")
        } header: {
            HStack {
                Text("Toolchain")
                Spacer()
                if model.isProbing { ProgressView().controlSize(.small) }
                Button("Check Again") { model.probeToolchains() }
                    .disabled(model.isProbing)
            }
        } footer: {
            Text(LocalizedStringKey(
                "Install missing pieces with rustup, for example `rustup target add <target>` or "
                + "`rustup component add rust-src`, run in the Cargo folder."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var activeToolchain: some View {
        if let status {
            if let problem = status.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(status.activeToolchain ?? String(localized: "Unknown")).textSelection(.enabled)
                    if let rustc = status.rustcVersion {
                        Text(rustc).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Text("Detecting…").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func installedLabel(_ name: String, installed: Bool?) -> some View {
        switch installed {
        case true?:
            Label(name, systemImage: "checkmark.circle.fill").foregroundStyle(.primary)
        case false?:
            Label("\(name) not installed", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        case nil:
            Text(name).foregroundStyle(.secondary)
        }
    }
}

/// The Cargo build and run settings of one root, stored in `.codeedit/cargo-settings.json`.
private struct CargoSettingsSections: View {
    let root: CargoRoot
    let path: String
    @Bindable var settings: ProjectSettingsFile<CargoProjectSettings>

    private var rootSettings: Binding<CargoProjectSettings.Root> {
        Binding(
            get: { settings.value.root(path) },
            set: { settings.value.roots[path] = $0 }
        )
    }

    var body: some View {
        Section {
            Picker("Profile", selection: rootSettings.profile) {
                ForEach(root.profiles) { profile in
                    Text(profile.name).tag(profile.name)
                }
            }
            if let profile = root.profiles.first(where: { $0.name == rootSettings.wrappedValue.profile }),
               !profile.summary.isEmpty {
                LabeledContent("Profile Settings", value: profile.summary)
            }
            Picker("Target", selection: rootSettings.target) {
                Text("Host").tag(String?.none)
                ForEach(root.toolchainFile?.targets ?? [], id: \.self) { target in
                    Text(target).tag(String?.some(target))
                }
            }
            Toggle("All Features", isOn: rootSettings.allFeatures)
            Toggle("No Default Features", isOn: rootSettings.noDefaultFeatures)
            if !root.selectableFeatures.isEmpty && !rootSettings.wrappedValue.allFeatures {
                ForEach(root.selectableFeatures, id: \.self) { feature in
                    Toggle(feature, isOn: featureBinding(feature))
                }
            }
        } header: {
            Text("Build")
        } footer: {
            Text("Used by the generated Cargo tasks. Saved in .codeedit/\(CargoProjectSettings.fileName).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Run") {
            Picker("Run Target", selection: rootSettings.runTarget) {
                Text("First Binary").tag(CargoRunTarget?.none)
                ForEach(root.runnableTargets) { target in
                    Text(target.title).tag(CargoRunTarget?.some(target))
                }
            }
            TextField("Arguments", text: rootSettings.runArguments, prompt: Text("Passed after --"))
            VStack(alignment: .leading, spacing: 6) {
                Text("Environment")
                KeyValueListEditor(rows: rootSettings.environment, emptyText: "No Environment Variables")
                    .frame(minHeight: 110)
            }
        }
    }

    private func featureBinding(_ feature: String) -> Binding<Bool> {
        Binding(
            get: { rootSettings.wrappedValue.features.contains(feature) },
            set: { isOn in
                var value = rootSettings.wrappedValue
                value.features.removeAll { $0 == feature }
                if isOn { value.features.append(feature) }
                rootSettings.wrappedValue = value
            }
        )
    }
}
