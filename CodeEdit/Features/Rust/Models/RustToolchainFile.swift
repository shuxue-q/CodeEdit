//
//  RustToolchainFile.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

/// A `rust-toolchain.toml` (or legacy one-line `rust-toolchain`) file that pins a project's Rust
/// toolchain. rustup uses the nearest one at or above the directory a command runs in.
struct RustToolchainFile: Equatable, Sendable {
    /// The file names rustup looks for, in its order of preference.
    static let fileNames = ["rust-toolchain", "rust-toolchain.toml"]

    /// The file that was read.
    var url: URL
    /// The pinned channel, such as `1.97.1`, `stable` or `nightly-2026-01-01`.
    var channel: String?
    /// A custom toolchain directory (`path = …`), used instead of a channel.
    var path: String?
    /// Components to install with the toolchain, such as `rust-src`.
    var components: [String] = []
    /// Target triples to install with the toolchain.
    var targets: [String] = []
    /// The rustup profile (`minimal`, `default`, `complete`).
    var profile: String?

    /// Parses toolchain file text. A legacy file holds just the channel name; a TOML file has a
    /// `[toolchain]` table.
    /// - Parameters:
    ///   - text: The file contents.
    ///   - url: The file the text came from.
    static func parse(_ text: String, url: URL) -> Self {
        var file = Self(url: url)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isTOML = url.pathExtension == "toml" || trimmed.contains("[toolchain]") || trimmed.contains("=")
        guard isTOML else {
            file.channel = trimmed.isEmpty ? nil : trimmed
            return file
        }
        let toolchain = TOMLDocument.parse(text).root["toolchain"]?.table ?? TOMLTable()
        file.channel = toolchain["channel"]?.string
        file.path = toolchain["path"]?.string
        file.components = toolchain["components"]?.strings ?? []
        file.targets = toolchain["targets"]?.strings ?? []
        file.profile = toolchain["profile"]?.string
        return file
    }

    /// Reads the toolchain file directly in `directory`, preferring `rust-toolchain` like rustup.
    static func read(in directory: URL) -> Self? {
        for name in fileNames {
            let url = directory.appending(path: name)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            return parse(text, url: url)
        }
        return nil
    }

    /// Finds the toolchain file rustup would use for `directory`: the nearest one at or above it,
    /// stopping at `boundary` (the workspace folder).
    static func nearest(to directory: URL, within boundary: URL) -> Self? {
        let boundaryPath = boundary.standardizedFileURL.path
        var current = directory.standardizedFileURL
        while true {
            if let file = read(in: current) { return file }
            guard current.path != boundaryPath, current.path.hasPrefix(boundaryPath), current.path != "/" else {
                return nil
            }
            current = current.deletingLastPathComponent().standardizedFileURL
        }
    }
}
