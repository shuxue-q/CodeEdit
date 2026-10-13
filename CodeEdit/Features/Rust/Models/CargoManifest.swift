//
//  CargoManifest.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

/// The parts of a `Cargo.toml` CodeEdit needs to find Cargo projects: the package name and whether
/// the manifest is a workspace root, with its `members` and `exclude` lists.
///
/// Read line by line without a TOML dependency. Only table headers and the two string arrays of the
/// `[workspace]` table are understood, which is all project discovery needs.
struct CargoManifest: Equatable, Sendable {
    /// The file name of a Cargo manifest.
    static let fileName = "Cargo.toml"

    /// The `name` of the `[package]` table, if any.
    var packageName: String?
    /// Whether the manifest has a `[workspace]` table.
    var isWorkspace = false
    /// The `members` of the `[workspace]` table: relative paths or globs.
    var workspaceMembers: [String] = []
    /// The `exclude` list of the `[workspace]` table: relative paths of directories that are not members.
    var workspaceExclude: [String] = []

    /// Reads the manifest at `url`, or returns `nil` when it cannot be read.
    /// - Parameter url: The `Cargo.toml` file.
    static func read(at url: URL) -> Self? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// Parses the text of a `Cargo.toml`.
    /// - Parameter text: The manifest's contents.
    /// - Returns: What the manifest says about its package and workspace.
    static func parse(_ text: String) -> Self {
        var manifest = Self()
        var table = ""
        var openArray: OpenArray?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if var array = openArray {
                array.values += quotedStrings(in: line)
                if line.contains("]") {
                    manifest.store(array.values, for: array.key)
                    openArray = nil
                } else {
                    openArray = array
                }
            } else if line.hasPrefix("[") {
                table = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                // `[workspace.dependencies]` and the like define the workspace table too.
                if table == "workspace" || table.hasPrefix("workspace.") {
                    manifest.isWorkspace = true
                }
            } else {
                openArray = manifest.readEntry(line, in: table)
            }
        }
        return manifest
    }

    /// A string array that continues on the following lines.
    private struct OpenArray {
        let key: String
        var values: [String]
    }

    /// Reads a `key = value` line of `table`. Returns the array it opens when the value continues on the
    /// next lines.
    private mutating func readEntry(_ line: String, in table: String) -> OpenArray? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        if table == "package" && key == "name" {
            packageName = Self.quotedStrings(in: value).first
            return nil
        }
        guard table == "workspace", key == "members" || key == "exclude", value.hasPrefix("[") else { return nil }
        if value.contains("]") {
            store(Self.quotedStrings(in: value), for: key)
            return nil
        }
        return OpenArray(key: key, values: Self.quotedStrings(in: value))
    }

    private mutating func store(_ values: [String], for key: String) {
        if key == "members" {
            workspaceMembers = values
        } else {
            workspaceExclude = values
        }
    }

    /// `line` without a `#` comment, ignoring `#` inside quoted strings.
    private static func stripComment(_ line: String) -> String {
        var quote: Character?
        for index in line.indices {
            let char = line[index]
            if let open = quote {
                if char == open { quote = nil }
            } else if char == "\"" || char == "'" {
                quote = char
            } else if char == "#" {
                return String(line[..<index])
            }
        }
        return line
    }

    /// The contents of the `"…"` and `'…'` strings in `text`, in order.
    private static func quotedStrings(in text: String) -> [String] {
        var strings: [String] = []
        var current = ""
        var quote: Character?
        for char in text {
            if let open = quote {
                if char == open {
                    strings.append(current)
                    current = ""
                    quote = nil
                } else {
                    current.append(char)
                }
            } else if char == "\"" || char == "'" {
                quote = char
            }
        }
        return strings
    }
}
