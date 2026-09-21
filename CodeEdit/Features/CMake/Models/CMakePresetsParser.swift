//
//  CMakePresetsParser.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/11/26.
//

import Foundation

/// Loads configure/build presets without invoking CMake or changing project files.
struct CMakePresetsParser {
    private struct Definition {
        var fields: [String: CMakeJSON]
        let file: URL
    }

    private var files: [URL: Set<URL>] = [:]
    private var configure: [String: Definition] = [:]
    private var build: [String: Definition] = [:]
    private var configureOrder: [String] = []
    private var buildOrder: [String] = []
    let sourceDirectory: URL
    let environment: [String: String]

    static func load(
        at directory: URL,
        environment: [String: String]
    ) throws -> (configure: [CMakePreset], build: [CMakePreset]) {
        let directory = URL(fileURLWithPath: directory.path, isDirectory: true)
        var parser = Self(sourceDirectory: directory, environment: environment)
        let shared = directory.appendingPathComponent("CMakePresets.json")
        let user = directory.appendingPathComponent("CMakeUserPresets.json")
        if FileManager.default.fileExists(atPath: shared.path) { try parser.read(shared) }
        if FileManager.default.fileExists(atPath: user.path) {
            let included = parser.files[shared.resolvingSymlinksInPath()] == nil ? nil : shared
            try parser.read(user, implicitInclude: included)
        }
        let configure = try parser.configureOrder.compactMap { try parser.preset($0, definitions: parser.configure) }
        let build = try parser.buildOrder.compactMap { try parser.preset($0, definitions: parser.build, isBuild: true) }
        return (configure, build)
    }

    private mutating func read(_ url: URL, visiting: Set<URL> = [], implicitInclude: URL? = nil) throws {
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        guard !visiting.contains(url) else { throw CMakeParseError("Preset include cycle: \(url.path)") }
        guard files[url] == nil else { return }
        do {
            let document = try JSONDecoder().decode(CMakeJSON.self, from: Data(contentsOf: url))
            guard let version = document["version"]?.integer, (1...10).contains(version) else {
                throw CMakeParseError("Supported preset schema versions are 1–10.")
            }
            var included: Set<URL> = []
            if let implicitInclude { included.insert(implicitInclude.resolvingSymlinksInPath()) }
            if let includes = document["include"] {
                guard version >= 4, let paths = includes.strings else {
                    throw CMakeParseError("'include' requires an array of paths and schema version 4 or newer.")
                }
                for path in paths {
                    let expander = CMakePresetExpansion(
                        sourceDirectory: sourceDirectory, file: url, parent: environment
                    )
                    if path.contains("$"), version < 7 {
                        throw CMakeParseError("Include macros require schema version 7 or newer.")
                    }
                    let expanded = try expander.expand(path, includeVersion: version)
                    let child = URL(fileURLWithPath: expanded, relativeTo: url.deletingLastPathComponent())
                        .standardizedFileURL.resolvingSymlinksInPath()
                    try read(child, visiting: visiting.union([url]))
                    included.insert(child)
                }
            }
            for child in included { included.formUnion(files[child] ?? []) }
            files[url] = included
            try add(document["configurePresets"], file: url, isBuild: false)
            try add(document["buildPresets"], file: url, isBuild: true)
        } catch {
            throw CMakeParseError("\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private mutating func add(_ value: CMakeJSON?, file: URL, isBuild: Bool) throws {
        guard let value else { return }
        guard let presets = value.array else { throw CMakeParseError("Expected a preset array.") }
        for preset in presets {
            guard let fields = preset.object, let name = preset["name"]?.string, !name.isEmpty else {
                throw CMakeParseError("Each preset needs a nonempty name.")
            }
            for key in ["cacheVariables", "environment"] where fields[key] != nil {
                guard fields[key]?.object != nil else { throw CMakeParseError("'\(key)' must be an object.") }
            }
            for key in ["hidden", "inheritConfigureEnvironment"] where fields[key] != nil {
                guard fields[key]?.bool != nil else { throw CMakeParseError("'\(key)' must be a boolean.") }
            }
            guard (isBuild ? build[name] : configure[name]) == nil else {
                throw CMakeParseError("Duplicate preset '\(name)'.")
            }
            let definition = Definition(fields: fields, file: file)
            if isBuild {
                build[name] = definition
                buildOrder.append(name)
            } else {
                configure[name] = definition
                configureOrder.append(name)
            }
        }
    }

    private func resolve(
        _ name: String,
        definitions: [String: Definition],
        visiting: Set<String> = []
    ) throws -> Definition {
        guard !visiting.contains(name) else { throw CMakeParseError("Preset inheritance cycle at '\(name)'.") }
        guard let definition = definitions[name] else { throw CMakeParseError("Unknown preset '\(name)'.") }
        var fields: [String: CMakeJSON] = [:]
        if let inherits = definition.fields["inherits"] {
            guard let parents = inherits.string.map({ [$0] }) ?? inherits.strings else {
                throw CMakeParseError("Invalid inherits in '\(name)'.")
            }
            // Earlier parents have precedence. Expand macros only after merging into the child.
            for parent in parents.reversed() {
                let resolved = try resolve(parent, definitions: definitions, visiting: visiting.union([name]))
                guard resolved.file == definition.file || files[definition.file]?.contains(resolved.file) == true else {
                    throw CMakeParseError("Preset '\(name)' must include the file defining '\(parent)'.")
                }
                var inherited = resolved.fields
                for key in ["name", "hidden", "inherits", "description", "displayName"] { inherited[key] = nil }
                if case .null = inherited["condition"] { inherited["condition"] = nil }
                merge(inherited, into: &fields)
            }
        }
        merge(definition.fields, into: &fields)
        return Definition(fields: fields, file: definition.file)
    }

    private func merge(_ source: [String: CMakeJSON], into target: inout [String: CMakeJSON]) {
        for (key, value) in source {
            if ["cacheVariables", "environment"].contains(key), let values = value.object {
                target[key] = .object((target[key]?.object ?? [:]).merging(values) { _, new in new })
            } else {
                target[key] = value
            }
        }
    }

    private func preset(
        _ name: String,
        definitions: [String: Definition],
        isBuild: Bool = false
    ) throws -> CMakePreset? {
        let definition = try resolve(name, definitions: definitions)
        let fields = definition.fields
        guard fields["hidden"]?.bool != true else { return nil }
        var presetEnvironment = fields["environment"]?.object ?? [:]
        if isBuild {
            guard let configureName = fields["configurePreset"]?.string else {
                throw CMakeParseError("Build preset '\(name)' has no configurePreset.")
            }
            let configured = try resolve(configureName, definitions: configure)
            guard configured.file == definition.file || files[definition.file]?.contains(configured.file) == true else {
                throw CMakeParseError("Build preset '\(name)' must include its configure preset file.")
            }
            guard try preset(configureName, definitions: configure) != nil else { return nil }
            if fields["inheritConfigureEnvironment"]?.bool != false {
                presetEnvironment = (configured.fields["environment"]?.object ?? [:])
                    .merging(presetEnvironment) { _, new in new }
            }
        }
        let expansion = CMakePresetExpansion(
            sourceDirectory: sourceDirectory, file: definition.file, parent: environment,
            presetName: name, generator: fields["generator"]?.string ?? "", environment: presetEnvironment
        )
        guard try expansion.enabled(fields["condition"]) else { return nil }
        func expanded(_ key: String) throws -> String? {
            guard let value = fields[key] else { return nil }
            guard let string = value.string else { throw CMakeParseError("'\(key)' must be a string in '\(name)'.") }
            return try expansion.expand(string)
        }
        var cache: [String: String] = [:]
        for (key, value) in fields["cacheVariables"]?.object ?? [:] {
            if case .null = value { continue }
            let value = value.object?["value"] ?? value
            guard let string = value.string ?? value.bool.map({ $0 ? "TRUE" : "FALSE" }) else {
                throw CMakeParseError("Invalid cache variable '\(key)' in '\(name)'.")
            }
            cache[key] = try expansion.expand(string)
        }
        let binary = try expanded("binaryDir").map {
            URL(fileURLWithPath: $0, relativeTo: sourceDirectory).standardizedFileURL.path
        }
        return try CMakePreset(
            name: name, displayName: fields["displayName"]?.string, generator: fields["generator"]?.string,
            binaryDirectory: binary, toolchainFile: expanded("toolchainFile") ?? cache["CMAKE_TOOLCHAIN_FILE"],
            configurePreset: fields["configurePreset"]?.string, configuration: expanded("configuration"),
            cacheVariables: cache, environment: expansion.resolvedEnvironment()
        )
    }
}

/// JSON values retain null tombstones during preset inheritance.
indirect enum CMakeJSON: Decodable, Sendable {
    case object([String: CMakeJSON]), array([CMakeJSON]), string(String), bool(Bool), integer(Int), number(Double), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: Self].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([Self].self))
        }
    }

    subscript(_ key: String) -> Self? { object?[key] }
    var object: [String: Self]? { if case let .object(value) = self { return value }; return nil }
    var array: [Self]? { if case let .array(value) = self { return value }; return nil }
    var string: String? { if case let .string(value) = self { return value }; return nil }
    var bool: Bool? { if case let .bool(value) = self { return value }; return nil }
    var integer: Int? { if case let .integer(value) = self { return value }; return nil }
    var strings: [String]? {
        guard let array, array.allSatisfy({ $0.string != nil }) else { return nil }
        return array.compactMap(\.string)
    }
}
