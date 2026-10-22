//
//  ProjectOverviewPane.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import SwiftUI

/// The project editor's Overview section for workspaces that combine toolchains: the projects
/// found, how they build each other, the installed tool versions and the language servers.
struct ProjectOverviewPane: View {
    let model: ProjectInventoryModel
    let flutterWorkspace: FlutterWorkspace?
    /// Shows another project editor section.
    let select: (ProjectEditorState.Section) -> Void

    @Service private var lspService: LSPService

    var body: some View {
        Form {
            if let inventory = model.inventory {
                componentsSection(inventory)
                linksSection(inventory)
                toolchainsSection(inventory)
            } else {
                Section {
                    LabeledContent("Components") {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            LanguageServerStatusSection(lspService: lspService)
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("ProjectEditorOverview")
    }

    // MARK: - Components

    @ViewBuilder
    private func componentsSection(_ inventory: ProjectInventory) -> some View {
        Section {
            ForEach(inventory.components) { component in
                Button {
                    if let section = section(for: component) { select(section) }
                } label: {
                    ComponentRow(component: component)
                }
                .buttonStyle(.plain)
                .disabled(section(for: component) == nil)
                .help(component.directory.path)
            }
        } header: {
            HStack {
                Text("Components")
                Spacer()
                if model.isScanning { ProgressView().controlSize(.small) }
                Button("Rescan") { model.reload() }
                    .disabled(model.isScanning)
                    .accessibilityIdentifier("ProjectOverviewRescan")
            }
        } footer: {
            Text(LocalizedStringKey(
                "Found from pubspec.yaml, CMakeLists.txt and Cargo.toml files. Third-party and generated "
                + "projects are listed but not built."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func section(for component: ProjectComponent) -> ProjectEditorState.Section? {
        guard component.role == .primary else { return nil }
        switch component.kind.toolchain {
        case .flutter: return flutterWorkspace?.project == nil ? nil : .flutter
        case .cmake: return component.kind == .cmakeProject ? .cpp : nil
        case .cargo: return .rust
        }
    }

    @ViewBuilder
    private func linksSection(_ inventory: ProjectInventory) -> some View {
        Section {
            if inventory.links.isEmpty {
                Text("No build connections were found between the projects.")
                    .foregroundStyle(.secondary)
            }
            ForEach(inventory.links) { link in
                LabeledContent {
                    Text(link.evidence)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                } label: {
                    Text(linkSentence(link, in: inventory))
                }
            }
        } header: {
            Text("Connections")
        } footer: {
            Text("Detected from the build files' text; a mention of CMake or Cargo is taken as a build step.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func linkSentence(_ link: ProjectLink, in inventory: ProjectInventory) -> String {
        let source = inventory.component(link.source)
        let target = inventory.component(link.target)
        let kind = target?.kind.title ?? ""
        let sourceName = source?.name ?? link.source
        let targetName = target?.name ?? link.target
        return String(localized: "\(sourceName) \(link.summary) \(targetName) (\(kind))")
    }

    // MARK: - Toolchains

    @ViewBuilder
    private func toolchainsSection(_ inventory: ProjectInventory) -> some View {
        Section {
            if inventory.flutter != nil {
                LabeledContent("Flutter") {
                    if let sdk = flutterWorkspace?.sdk {
                        Text(flutterVersion(sdk)).textSelection(.enabled)
                    } else if flutterWorkspace?.hasLocatedSDK == true {
                        missing(String(localized: "Not found on PATH"))
                    } else {
                        Text("Detecting…").foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(inventory.cargoRoots) { root in
                LabeledContent(rustLabel(root, in: inventory)) {
                    rustSummary(root)
                }
            }
            if inventory.toolchains.contains(.cmake) {
                LabeledContent("CMake") {
                    if let version = model.toolchainStatus?.cmakeVersion {
                        Text(version)
                    } else if model.toolchainStatus?.checkedCMake == true {
                        missing(String(localized: "Not found on PATH"))
                    } else {
                        Text("Detecting…").foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                Text("Toolchains")
                Spacer()
                if model.isProbing { ProgressView().controlSize(.small) }
                Button("Check Again") { model.probeToolchains() }
                    .disabled(model.isProbing)
            }
        } footer: {
            Text("Read from the tools in your login shell PATH. Checking never installs a toolchain.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func rustLabel(_ root: CargoRoot, in inventory: ProjectInventory) -> String {
        let path = inventory.relativePath(of: root.directory)
        return path == "." ? "Rust" : "Rust (\(path)/)"
    }

    @ViewBuilder
    private func rustSummary(_ root: CargoRoot) -> some View {
        if let status = model.rustStatus(for: root) {
            if let problem = status.problem {
                missing(problem)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(status.activeToolchain ?? status.rustcVersion ?? String(localized: "Unknown"))
                        .textSelection(.enabled)
                    if let file = root.toolchainFile {
                        Text("Pinned by \(file.url.lastPathComponent)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Text("Detecting…").foregroundStyle(.secondary)
        }
    }

    private func flutterVersion(_ sdk: FlutterSDK) -> String {
        var parts = [sdk.version ?? String(localized: "Unknown")]
        if let channel = sdk.channel { parts.append(channel) }
        if let dart = sdk.dartVersion { parts.append("Dart \(dart)") }
        return parts.joined(separator: " · ")
    }

    private func missing(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
            .lineLimit(3)
    }
}

/// One row of the components list.
private struct ComponentRow: View {
    let component: ProjectComponent

    private var location: String {
        component.relativePath == "." ? String(localized: "Workspace root") : component.relativePath
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: ProjectToolchainSymbol.name(for: component.kind.toolchain))
                .foregroundStyle(component.role == .primary ? Color.accentColor : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(component.name).fontWeight(.medium)
                    if let detail = component.detail {
                        Text(detail).foregroundStyle(.secondary)
                    }
                }
                Text("\(component.kind.title) · \(location)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(component.role.title)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// SF Symbols for the toolchains, shared by the project editor and the scheme menu.
enum ProjectToolchainSymbol {
    static func name(for toolchain: ProjectToolchain) -> String {
        switch toolchain {
        case .flutter: "macwindow.on.rectangle"
        case .cmake: "hammer"
        case .cargo: "shippingbox"
        }
    }
}

/// The detected language servers for the workspace's languages.
private struct LanguageServerStatusSection: View {
    @ObservedObject var lspService: LSPService

    private let servers: [(title: LocalizedStringKey, languageId: String)] = [
        ("Dart analysis server", "dart"),
        ("clangd", "cpp"),
        ("rust-analyzer", "rust"),
        ("neocmakelsp", "cmake")
    ]

    var body: some View {
        Section {
            ForEach(servers, id: \.languageId) { server in
                LabeledContent(server.title) {
                    if let binary = lspService.detectedServers[server.languageId] {
                        Text(binary.execPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(binary.execPath)
                    } else {
                        Text("Not found").foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                Text("Language Servers")
                Spacer()
                Button("Detect") {
                    Task { await lspService.redetectServers() }
                }
            }
        } footer: {
            Text("Paths chosen in Settings › Language Servers take precedence.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task {
            if lspService.detectedServers.isEmpty {
                await lspService.redetectServers()
            }
        }
    }
}
