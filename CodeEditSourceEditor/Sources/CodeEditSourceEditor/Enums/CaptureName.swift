//
//  CaptureNames.swift
//  CodeEditSourceEditor
//
//  Created by Lukas Pistrol on 16.08.22.
//

/// A collection of possible syntax capture types. Represented by an integer for memory efficiency, and with the
/// ability to convert to and from strings for ease of use with tools.
///
/// This is `Int8` raw representable for memory considerations. In large documents there can be *lots* of these created
/// and passed around, so representing them with a single integer is preferable to a string to save memory.
///
public enum CaptureName: Int8, CaseIterable, Sendable {
    case include
    case constructor
    case keyword
    case boolean
    case `repeat`
    case conditional
    case tag
    case comment
    case variable
    case property
    case function
    case method
    case number
    case float
    case string
    case type
    case parameter
    case typeAlternate
    case variableBuiltin
    case keywordReturn
    case keywordFunction
    case constant
    case `operator`
    case label
    /// Rainbow bracket nesting levels. Only produced by the bracket depth pass, never by grammar queries.
    /// See ``bracketLevel(_:)``.
    case bracketLevel0
    case bracketLevel1
    case bracketLevel2
    case bracketLevel3
    case bracketLevel4
    case bracketLevel5

    /// The number of distinct rainbow bracket levels before the colors cycle.
    static let bracketLevelCount = 6

    /// The capture used to color a bracket at the given nesting depth. Depths wrap around every
    /// ``bracketLevelCount`` levels.
    /// - Parameter depth: The zero-based nesting depth of the bracket pair.
    static func bracketLevel(_ depth: Int) -> CaptureName {
        let levels: [CaptureName] = [
            .bracketLevel0, .bracketLevel1, .bracketLevel2, .bracketLevel3, .bracketLevel4, .bracketLevel5
        ]
        return levels[((depth % bracketLevelCount) + bracketLevelCount) % bracketLevelCount]
    }

    /// The rainbow level index (`0..<bracketLevelCount`) if this is a bracket level capture.
    var bracketLevelIndex: Int? {
        switch self {
        case .bracketLevel0: return 0
        case .bracketLevel1: return 1
        case .bracketLevel2: return 2
        case .bracketLevel3: return 3
        case .bracketLevel4: return 4
        case .bracketLevel5: return 5
        default: return nil
        }
    }

    var alternate: CaptureName {
        switch self {
        case .type:
            return .typeAlternate
        default:
            return self
        }
    }

    /// Exact matches for base capture names, plus tree-sitter dotted specials that must win
    /// over their prefix (e.g. `keyword.return`) and LSP semantic token type names
    /// (e.g. `namespace`, `macro`).
    private static let nameMap: [String: CaptureName] = [
        "include": .include,
        "constructor": .constructor,
        "keyword": .keyword,
        "boolean": .boolean,
        "repeat": .repeat,
        "conditional": .conditional,
        "tag": .tag,
        "comment": .comment,
        "variable": .variable,
        "property": .property,
        "function": .function,
        "method": .method,
        "number": .number,
        "float": .float,
        "string": .string,
        "character": .string,
        "type": .type,
        "parameter": .parameter,
        "type_alternate": .typeAlternate,
        "attribute": .typeAlternate,
        "variable.builtin": .variableBuiltin,
        "keyword.return": .keywordReturn,
        "keyword.function": .keywordFunction,
        "constant": .constant,
        "macro": .constant,
        "enumMember": .constant,
        "operator": .operator,
        "label": .label,
        // LSP semantic token type names without a tree-sitter equivalent
        "module": .type,
        "namespace": .type,
        "class": .type,
        "struct": .type,
        "enum": .type,
        "interface": .type,
        "typeParameter": .type,
        "typeAlias": .type,
        "concept": .type
    ]

    /// Returns a specific capture name case from a given string.
    ///
    /// Dotted names (tree-sitter's `function.builtin`, `constant.builtin`, …) fall back to
    /// progressively shorter prefixes when no exact match exists, mirroring how editors like
    /// Neovim resolve capture names, so whole capture families map without explicit entries.
    /// - Note: See ``CaptureName`` docs for why this enum isn't a raw representable.
    /// - Parameter string: A string to get the capture name from
    /// - Returns: A `CaptureNames` case
    public static func fromString(_ string: String?) -> CaptureName? {
        guard let string, !string.isEmpty else { return nil }
        var candidate = Substring(string)
        while true {
            if let capture = nameMap[String(candidate)] {
                return capture
            }
            guard let lastDot = candidate.lastIndex(of: ".") else { return nil }
            candidate = candidate[..<lastDot]
        }
    }

    /// See ``CaptureName`` docs for why this enum isn't a raw representable.
    var stringValue: String {
        switch self {
        case .include:
            return "include"
        case .constructor:
            return "constructor"
        case .keyword:
            return "keyword"
        case .boolean:
            return "boolean"
        case .repeat:
            return "`repeat`"
        case .conditional:
            return "conditional"
        case .tag:
            return "tag"
        case .comment:
            return "comment"
        case .variable:
            return "variable"
        case .property:
            return "property"
        case .function:
            return "function"
        case .method:
            return "method"
        case .number:
            return "number"
        case .float:
            return "float"
        case .string:
            return "string"
        case .type:
            return "type"
        case .parameter:
            return "parameter"
        case .typeAlternate:
            return "typeAlternate"
        case .variableBuiltin:
            return "variableBuiltin"
        case .keywordReturn:
            return "keywordReturn"
        case .keywordFunction:
            return "keywordFunction"
        case .constant:
            return "constant"
        case .operator:
            return "operator"
        case .label:
            return "label"
        case .bracketLevel0:
            return "bracketLevel0"
        case .bracketLevel1:
            return "bracketLevel1"
        case .bracketLevel2:
            return "bracketLevel2"
        case .bracketLevel3:
            return "bracketLevel3"
        case .bracketLevel4:
            return "bracketLevel4"
        case .bracketLevel5:
            return "bracketLevel5"
        }
    }
}

extension CaptureName: CustomDebugStringConvertible {
    public var debugDescription: String { stringValue }
}
