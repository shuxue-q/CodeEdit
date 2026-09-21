//
//  CMakePresetExpansion.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/11/26.
//

import Foundation

/// Expands preset fields in the selected child's context, with cycle checks for environment references.
struct CMakePresetExpansion {
    let sourceDirectory: URL
    let file: URL
    let parent: [String: String]
    var presetName = ""
    var generator = ""
    var environment: [String: CMakeJSON] = [:]

    func expand(_ value: String, visiting: Set<String> = [], includeVersion: Int? = nil) throws -> String {
        let regex = try NSRegularExpression(pattern: #"\$(\w*)\{([^}]*)\}"#)
        let range = NSRange(value.startIndex..., in: value)
        var result = value
        for match in regex.matches(in: value, range: range).reversed() {
            let namespace = (value as NSString).substring(with: match.range(at: 1))
            let name = (value as NSString).substring(with: match.range(at: 2))
            let replacement: String
            if let version = includeVersion {
                guard namespace == "penv" || (version >= 9 && namespace.isEmpty &&
                    !["presetName", "generator"].contains(name)) else {
                    throw CMakeParseError("Unsupported macro in include path: \(namespace){\(name)}")
                }
            }
            switch namespace {
            case "env": replacement = try environmentValue(name, visiting: visiting) ?? ""
            case "penv": replacement = parent[name] ?? ""
            case "": replacement = try macro(name)
            default: throw CMakeParseError("Unsupported preset macro: $\(namespace){\(name)}")
            }
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        // Detect unterminated macros in the input, without interpreting dollar signs in expanded values.
        let unmatched = regex.stringByReplacingMatches(in: value, range: range, withTemplate: "")
        if unmatched.range(of: #"\$\w*\{"#, options: .regularExpression) != nil {
            throw CMakeParseError("Unclosed preset macro in '\(value)'.")
        }
        return result
    }

    private func macro(_ name: String) throws -> String {
        switch name {
        case "sourceDir": return sourceDirectory.path
        case "sourceParentDir": return sourceDirectory.deletingLastPathComponent().path
        case "sourceDirName": return sourceDirectory.lastPathComponent
        case "presetName": return presetName
        case "generator": return generator
        case "hostSystemName": return "Darwin"
        case "fileDir": return file.deletingLastPathComponent().path
        case "dollar": return "$"
        case "pathListSep": return ":"
        default: throw CMakeParseError("Unknown preset macro: ${\(name)}")
        }
    }

    private func environmentValue(_ name: String, visiting: Set<String> = []) throws -> String? {
        guard !visiting.contains(name) else { throw CMakeParseError("Environment reference cycle at '\(name)'.") }
        guard let value = environment[name] else { return parent[name] }
        if case .null = value { return nil }
        guard let string = value.string else {
            throw CMakeParseError("Environment variable '\(name)' must be a string.")
        }
        return try expand(string, visiting: visiting.union([name]))
    }

    func resolvedEnvironment() throws -> [String: String] {
        var result = parent
        for name in environment.keys { result[name] = try environmentValue(name) }
        return result
    }

    func enabled(_ condition: CMakeJSON?) throws -> Bool {
        guard let condition else { return true }
        if case .null = condition { return true }
        if let value = condition.bool { return value }
        return try enabledObject(condition)
    }

    private func enabledObject(_ condition: CMakeJSON) throws -> Bool {
        guard let type = condition["type"]?.string else { throw CMakeParseError("Invalid preset condition.") }
        switch type {
        case "const":
            guard let value = condition["value"]?.bool else { throw CMakeParseError("Invalid constant condition.") }
            return value
        case "allOf", "anyOf":
            guard let conditions = condition["conditions"]?.array else {
                throw CMakeParseError("Missing nested conditions.")
            }
            if type == "allOf" { return try conditions.allSatisfy { try enabled($0) } }
            return try conditions.contains { try enabled($0) }
        case "not":
            guard let nested = condition["condition"] else { throw CMakeParseError("Missing nested condition.") }
            return try !enabled(nested)
        default: return try comparison(condition, type: type)
        }
    }

    private func comparison(_ condition: CMakeJSON, type: String) throws -> Bool {
        func string(_ key: String) throws -> String {
            guard let value = condition[key]?.string else { throw CMakeParseError("Missing condition field '\(key)'.") }
            return try expand(value)
        }
        switch type {
        case "equals", "notEquals":
            let equal = try string("lhs") == string("rhs")
            return type == "equals" ? equal : !equal
        case "inList", "notInList":
            guard let list = condition["list"]?.strings else { throw CMakeParseError("Invalid condition list.") }
            let contains = try list.map { try expand($0) }.contains(string("string"))
            return type == "inList" ? contains : !contains
        case "matches", "notMatches":
            let regex = try NSRegularExpression(pattern: string("regex"))
            let value = try string("string")
            let matches = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
            return type == "matches" ? matches : !matches
        default: throw CMakeParseError("Unknown preset condition '\(type)'.")
        }
    }
}
