//
//  TOMLDocument.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

/// A TOML value. Dates and times are kept as their source text.
indirect enum TOMLValue: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case float(Double)
    case boolean(Bool)
    case dateTime(String)
    case array([TOMLValue])
    case table(TOMLTable)

    /// The value as a string, when it is one.
    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// The value as an integer, when it is one.
    var integer: Int? {
        if case .integer(let value) = self { return value }
        return nil
    }

    /// The value as a Boolean, when it is one.
    var boolean: Bool? {
        if case .boolean(let value) = self { return value }
        return nil
    }

    /// The value as an array, when it is one.
    var array: [TOMLValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    /// The value as a table, when it is one.
    var table: TOMLTable? {
        if case .table(let value) = self { return value }
        return nil
    }

    /// The strings of an array value, skipping elements of other types.
    var strings: [String] {
        array?.compactMap(\.string) ?? []
    }

    /// The value written back as TOML-like text, for display.
    var displayText: String {
        switch self {
        case .string(let value): return value
        case .integer(let value): return String(value)
        case .float(let value): return String(value)
        case .boolean(let value): return value ? "true" : "false"
        case .dateTime(let value): return value
        case .array(let values): return "[" + values.map(\.displayText).joined(separator: ", ") + "]"
        case .table(let table):
            return "{ " + table.keys.map { "\($0) = \(table[$0]?.displayText ?? "")" }.joined(separator: ", ") + " }"
        }
    }

    /// Looks up `key` when the value is a table.
    subscript(key: String) -> TOMLValue? {
        table?[key]
    }
}

/// A TOML table that remembers the order its keys were defined in.
struct TOMLTable: Equatable, Sendable {
    /// The keys in definition order.
    private(set) var keys: [String] = []
    private var storage: [String: TOMLValue] = [:]

    /// Creates an empty table.
    init() {}

    /// The value for `key`. Setting a new key appends it to ``keys``; setting `nil` removes it.
    subscript(key: String) -> TOMLValue? {
        get { storage[key] }
        set {
            if let newValue {
                if storage.updateValue(newValue, forKey: key) == nil { keys.append(key) }
            } else if storage.removeValue(forKey: key) != nil {
                keys.removeAll { $0 == key }
            }
        }
    }

    /// Whether the table has no keys.
    var isEmpty: Bool { keys.isEmpty }

    /// The value at a dotted path such as `["package", "name"]`.
    func value(at path: [String]) -> TOMLValue? {
        guard let first = path.first else { return .table(self) }
        guard let value = storage[first] else { return nil }
        if path.count == 1 { return value }
        return value.table?.value(at: Array(path.dropFirst()))
    }

    /// The key/value pairs in definition order.
    var entries: [(key: String, value: TOMLValue)] {
        keys.compactMap { key in storage[key].map { (key, $0) } }
    }

    /// Runs `body` on the table at `path`, creating missing tables. A path segment holding an
    /// array of tables descends into its last element, as TOML's `[a.b]` after `[[a]]` does.
    mutating func withTable(at path: ArraySlice<String>, _ body: (inout TOMLTable) throws -> Void) throws {
        guard let first = path.first else {
            try body(&self)
            return
        }
        var child = storage[first] ?? .table(TOMLTable())
        switch child {
        case .table(var table):
            try table.withTable(at: path.dropFirst(), body)
            child = .table(table)
        case .array(var array):
            guard case .table(var table)? = array.last else {
                throw TOMLParseError(message: "'\(first)' is not a table")
            }
            try table.withTable(at: path.dropFirst(), body)
            array[array.count - 1] = .table(table)
            child = .array(array)
        default:
            throw TOMLParseError(message: "'\(first)' is already defined as a value")
        }
        self[first] = child
    }
}

/// A problem found while reading a TOML document.
struct TOMLParseError: Error, Equatable, Sendable {
    /// What went wrong.
    var message: String
    /// The 1-based line the problem was found on.
    var line: Int = 0
}

/// A parsed TOML document.
///
/// A small reader for the TOML 1.0 that Cargo and rustup files use: tables, arrays of tables,
/// dotted and quoted keys, basic and literal strings (including multi-line ones), integers in
/// all bases, floats, Booleans, dates (kept as text), arrays and inline tables. A malformed line
/// is reported in ``errors`` and skipped; the rest of the document still loads.
struct TOMLDocument: Equatable, Sendable {
    /// The top-level table.
    var root = TOMLTable()
    /// Problems found while parsing, in order.
    var errors: [TOMLParseError] = []

    /// The value at a dotted path, for example `["package", "name"]`.
    func value(at path: String...) -> TOMLValue? {
        root.value(at: path)
    }

    /// Parses TOML text.
    static func parse(_ text: String) -> Self {
        var parser = TOMLParser(text: text)
        return parser.parseDocument()
    }

    /// Reads and parses the file at `url`, or returns `nil` when it cannot be read.
    static func read(at url: URL) -> Self? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }
}
