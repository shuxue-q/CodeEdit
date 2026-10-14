//
//  ToolchainProbe.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

/// What rustup reports for one Cargo root.
struct RustToolchainStatus: Equatable, Sendable {
    /// Whether `rustup` is installed; without it only `rustc --version` is known.
    var hasRustup = false
    /// The toolchain rustup selects in the root, such as `1.97.1-aarch64-apple-darwin`.
    var activeToolchain: String?
    /// Why it is selected, such as `overridden by '…/rust-toolchain.toml'`.
    var activeReason: String?
    /// `rustc --version` in the root.
    var rustcVersion: String?
    /// Targets installed for the active toolchain; `nil` when unknown.
    var installedTargets: [String]?
    /// Components installed for the active toolchain, with host suffixes removed; `nil` when unknown.
    var installedComponents: [String]?
    /// Why the toolchain is unusable, such as a pinned toolchain that is not installed.
    var problem: String?

    /// Whether `target` is installed; `nil` when unknown.
    func hasTarget(_ target: String) -> Bool? {
        installedTargets.map { $0.contains(target) }
    }

    /// Whether `component` is installed; `nil` when unknown.
    func hasComponent(_ component: String) -> Bool? {
        installedComponents.map { $0.contains(component) }
    }
}

/// Versions of the command-line tools a hybrid workspace needs.
struct ToolchainStatus: Equatable, Sendable {
    /// `cmake --version`, such as `3.31.6`; `nil` when CMake is not installed.
    var cmakeVersion: String?
    /// Whether CMake was looked for.
    var checkedCMake = false
    /// Rust status per Cargo root folder path.
    var rust: [String: RustToolchainStatus] = [:]
}

/// Asks the installed tools for their versions. Every probe spawns processes; call it off the
/// main actor. Probes never install anything: rustup runs with `RUSTUP_AUTO_INSTALL=0`.
enum ToolchainProbe {
    /// Probes CMake (when `includeCMake`) and rustup for each Cargo root.
    static func probe(cargoRoots: [URL], includeCMake: Bool) -> ToolchainStatus {
        var environment = LanguageServerDetector.userShellEnvironment()
        environment["RUSTUP_AUTO_INSTALL"] = "0"
        let tools = LanguageServerDetector.locateExecutables(["cmake", "rustup", "rustc"])
        var status = ToolchainStatus()
        if includeCMake {
            status.checkedCMake = true
            if let cmake = tools["cmake"],
               let result = ToolProcess.run(cmake, ["--version"], environment: environment),
               result.succeeded {
                status.cmakeVersion = parseCMakeVersion(result.output)
            }
        }
        for root in cargoRoots {
            status.rust[root.standardizedFileURL.path] = probeRust(
                in: root,
                rustup: tools["rustup"],
                rustc: tools["rustc"],
                environment: environment
            )
        }
        return status
    }

    private static func probeRust(
        in directory: URL,
        rustup: String?,
        rustc: String?,
        environment: [String: String]
    ) -> RustToolchainStatus {
        var status = RustToolchainStatus(hasRustup: rustup != nil)
        if let rustup {
            let active = ToolProcess.run(rustup, ["show", "active-toolchain"], in: directory, environment: environment)
            if let result = active {
                if result.succeeded {
                    (status.activeToolchain, status.activeReason) = parseActiveToolchain(result.output)
                } else {
                    status.problem = firstLine(result.errorOutput) ?? "rustup could not select a toolchain."
                }
            }
            if let toolchain = status.activeToolchain {
                let targets = ToolProcess.run(
                    rustup, ["target", "list", "--installed", "--toolchain", toolchain],
                    in: directory, environment: environment
                )
                if let targets, targets.succeeded { status.installedTargets = lines(targets.output) }
                let components = ToolProcess.run(
                    rustup, ["component", "list", "--installed", "--toolchain", toolchain],
                    in: directory, environment: environment
                )
                if let components, components.succeeded {
                    status.installedComponents = lines(components.output).map(stripHostSuffix)
                }
            }
        }
        if status.problem == nil, let rustc,
           let result = ToolProcess.run(rustc, ["--version"], in: directory, environment: environment) {
            if result.succeeded {
                status.rustcVersion = firstLine(result.output)
            } else if status.activeToolchain == nil {
                status.problem = firstLine(result.errorOutput)
            }
        }
        return status
    }

    // MARK: - Parsing

    /// `cmake version 3.31.6` → `3.31.6`.
    static func parseCMakeVersion(_ output: String) -> String? {
        guard let line = firstLine(output) else { return nil }
        return line.components(separatedBy: " ").last
    }

    /// `1.97.1-aarch64-apple-darwin (overridden by '/x/rust-toolchain.toml')` → the toolchain and
    /// the reason. Newer rustup versions print the reason in parentheses too.
    static func parseActiveToolchain(_ output: String) -> (String?, String?) {
        guard let line = firstLine(output) else { return (nil, nil) }
        guard let open = line.firstIndex(of: "(") else {
            return (line.trimmingCharacters(in: .whitespaces), nil)
        }
        let toolchain = line[..<open].trimmingCharacters(in: .whitespaces)
        let reason = line[line.index(after: open)...].trimmingCharacters(in: CharacterSet(charactersIn: " )"))
        return (toolchain.isEmpty ? nil : toolchain, reason.isEmpty ? nil : reason)
    }

    /// `clippy-aarch64-apple-darwin` → `clippy`; `rust-src` stays as it is.
    static func stripHostSuffix(_ component: String) -> String {
        let hosts = ["-aarch64-apple-darwin", "-x86_64-apple-darwin", "-x86_64-unknown-linux-gnu",
                     "-aarch64-unknown-linux-gnu", "-x86_64-pc-windows-msvc"]
        for host in hosts where component.hasSuffix(host) {
            return String(component.dropLast(host.count))
        }
        return component
    }

    private static func firstLine(_ text: String) -> String? {
        lines(text).first
    }

    private static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
