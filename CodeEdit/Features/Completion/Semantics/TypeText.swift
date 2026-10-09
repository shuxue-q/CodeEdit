//
//  TypeText.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// A C or C++ type reduced to what completion ranking compares: its name and its pointer depth.
///
/// Qualifiers (`const`, `volatile`), references and elaborated specifiers (`struct`, `class`) are
/// dropped, inline namespaces (`std::__1::`) are collapsed, and a few spellings of the same type
/// (`unsigned`, `basic_string<char>`, `std::size_t`) are folded together. Template arguments are kept
/// as written, apart from whitespace. Whether two types are the same, or merely convertible, is decided
/// by ``match(_:candidateIsEnumerator:)``.
struct TypeText: Equatable, Hashable, Sendable, CustomStringConvertible {
    /// How well a candidate's type fits the type a slot expects.
    enum Match: Equatable, Sendable {
        /// The candidate cannot be told to fit. Never a penalty.
        case none
        /// The candidate converts implicitly to the expected type.
        case convertible
        /// The candidate has the expected type.
        case exact
    }

    /// The type name without qualifiers, references and pointer stars, for example `std::vector<int>`.
    let name: String
    /// How many `*` the type has.
    let pointerDepth: Int

    /// The type spelled out: the name followed by one `*` per pointer level.
    var description: String { name + String(repeating: "*", count: pointerDepth) }

    /// Creates a type from an already normalized `name`.
    init(name: String, pointerDepth: Int = 0) {
        self.name = name
        self.pointerDepth = pointerDepth
    }

    // MARK: - Parsing

    /// Words that qualify a type without being part of its name.
    private static let qualifiers: Set<String> = [
        "const", "volatile", "struct", "class", "enum", "union", "typename", "restrict", "__restrict",
        "register", "static", "extern", "constexpr", "mutable", "inline"
    ]

    /// Inline namespaces that standard library implementations put between `std::` and the name.
    private static let inlineNamespaces = ["__1::", "__cxx11::", "__debug::", "__gnu_cxx::"]

    /// Normalizes `text`, a type as the language server or the source spells it.
    ///
    /// - Returns: `nil` when `text` is empty or names no concrete type (`auto`, `decltype(…)`).
    static func parse(_ text: String) -> TypeText? {
        var words: [String] = []
        var current = ""
        var pointerDepth = 0
        var nesting = 0

        func flush() {
            if !current.isEmpty { words.append(current) }
            current = ""
        }
        for char in text {
            switch char {
            case "<", "(", "[":
                nesting += 1
                current.append(char)
            case ">", ")", "]":
                nesting = max(0, nesting - 1)
                current.append(char)
            default:
                if nesting > 0 {
                    current.append(char)
                } else if char == "*" {
                    flush()
                    pointerDepth += 1
                } else if char == "&" || char.isWhitespace {
                    flush()
                } else {
                    current.append(char)
                }
            }
        }
        flush()

        words = words.filter { !qualifiers.contains($0) }
        var name = words.joined(separator: " ")
        while name.hasPrefix("::") { name.removeFirst(2) }
        name = tidy(name)
        for namespace in inlineNamespaces {
            name = name.replacingOccurrences(of: namespace, with: "")
        }
        guard !name.isEmpty, name != "auto", !name.hasPrefix("decltype") else { return nil }
        return TypeText(name: canonicalName(name), pointerDepth: pointerDepth)
    }

    /// Removes the whitespace around punctuation inside template arguments.
    private static func tidy(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s*([,<>()\[\]*&])\s*"#, with: "$1", options: .regularExpression)
    }

    // MARK: - Canonical spellings

    /// The spelling shared by every way of writing the same type.
    private static func canonicalName(_ name: String) -> String {
        if let primitive = canonicalPrimitive(name) { return primitive }
        if name.range(of: #"^(std::)?basic_string<char(,.*)?>$"#, options: .regularExpression) != nil {
            return "std::string"
        }
        if name.range(of: #"^(std::)?basic_string_view<char(,.*)?>$"#, options: .regularExpression) != nil {
            return "std::string_view"
        }
        if name.hasPrefix("std::"), sizedAliases.contains(String(name.dropFirst(5))) {
            return String(name.dropFirst(5))
        }
        return name
    }

    /// C library typedefs that are the same type with or without `std::`.
    private static let sizedAliases: Set<String> = [
        "size_t", "ssize_t", "ptrdiff_t", "intptr_t", "uintptr_t", "int8_t", "int16_t", "int32_t", "int64_t",
        "uint8_t", "uint16_t", "uint32_t", "uint64_t"
    ]

    private static let primitiveWords: Set<String> = [
        "unsigned", "signed", "short", "long", "int", "char", "double", "float", "bool", "void", "wchar_t",
        "char16_t", "char32_t", "char8_t"
    ]

    /// `unsigned` → `unsigned int`, `long int` → `long`, `long unsigned int` → `unsigned long`; `nil` when
    /// `name` is not made of primitive type words.
    private static func canonicalPrimitive(_ name: String) -> String? {
        let words = name.split(separator: " ").map(String.init)
        guard !words.isEmpty, words.allSatisfy(primitiveWords.contains) else { return nil }
        let isUnsigned = words.contains("unsigned")
        let longs = words.filter { $0 == "long" }.count
        var base: String
        if let other = words.first(where: { !["unsigned", "signed", "long", "short", "int"].contains($0) }) {
            if other == "double" {
                return longs > 0 ? "long double" : "double"
            }
            guard other == "char" else { return other }
            return isUnsigned ? "unsigned char" : (words.contains("signed") ? "signed char" : "char")
        }
        if words.contains("short") {
            base = "short"
        } else if longs >= 2 {
            base = "long long"
        } else if longs == 1 {
            base = "long"
        } else {
            base = "int"
        }
        return isUnsigned ? "unsigned \(base)" : base
    }

    // MARK: - Matching

    private static let integerNames: Set<String> = [
        "char", "signed char", "unsigned char", "short", "unsigned short", "int", "unsigned int", "long",
        "unsigned long", "long long", "unsigned long long", "size_t", "ssize_t", "ptrdiff_t", "intptr_t",
        "uintptr_t", "int8_t", "int16_t", "int32_t", "int64_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t",
        "wchar_t", "char16_t", "char32_t", "char8_t"
    ]

    private static let floatingNames: Set<String> = ["float", "double", "long double"]

    /// Whether this is an arithmetic scalar (`int`, `size_t`, `double`, …) rather than a pointer or class.
    private var isNumeric: Bool {
        pointerDepth == 0 && (Self.integerNames.contains(name) || Self.floatingNames.contains(name))
    }

    private var isBool: Bool { pointerDepth == 0 && name == "bool" }

    private var isNullPointerType: Bool { pointerDepth == 0 && name == "std::nullptr_t" }

    /// How well a value of type `candidate` fits where this type is expected.
    ///
    /// Exact is the same normalized type. Convertible is an implicit arithmetic conversion (any of
    /// `int`, `long`, `size_t`, `double`, `float`, `char`, `bool`), an enumerator where a number is
    /// expected, a pointer where a `bool` is expected, `nullptr` or any pointer where a pointer is
    /// expected (when the expected type is `void *`), and `nullptr` where any pointer is expected.
    /// Everything else is `.none`: the ranker never penalizes it.
    /// - Parameter candidateIsEnumerator: Whether the candidate is an enumerator, whose type is its enum.
    func match(_ candidate: TypeText, candidateIsEnumerator: Bool = false) -> Match {
        if candidate == self { return .exact }
        if (isNumeric || isBool) && (candidate.isNumeric || candidate.isBool) { return .convertible }
        if isNumeric && candidateIsEnumerator && candidate.pointerDepth == 0 { return .convertible }
        if isBool && candidate.pointerDepth > 0 { return .convertible }
        if pointerDepth > 0 && candidate.isNullPointerType { return .convertible }
        if name == "void" && pointerDepth > 0 && candidate.pointerDepth > 0 { return .convertible }
        return .none
    }
}
