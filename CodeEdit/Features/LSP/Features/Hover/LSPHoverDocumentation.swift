//
//  LSPHoverDocumentation.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/16/26.
//

import AppKit
import Foundation
import SwiftUI

/// Represents a parsed language-server hover documentation payload.
struct LSPHoverDocumentation: Equatable {
    /// The extracted function, variable, or type declaration, if available.
    var declaration: LSPHoverDeclaration?

    /// The primary summary / description text.
    var summary: String?

    /// Structured parameters extracted from docstrings or markdown lists.
    var parameters: [LSPHoverParameter] = []

    /// Return value description, if available.
    var returns: String?

    /// Throws / exceptions description, if available.
    var throwsDescription: String?

    /// Callouts such as Note, Warning, Deprecated, or See Also.
    var callouts: [LSPHoverCallout] = []

    /// Additional discussion paragraphs, examples, or code blocks.
    var discussion: String?

    /// Estimated pixel height for popover sizing before first layout pass.
    var estimatedHeight: CGFloat {
        var height: CGFloat = 24

        if let declaration {
            let lineCount = max(1, declaration.code.components(separatedBy: "\n").count)
            height += CGFloat(lineCount) * 18 + 20
        }

        if let summary, !summary.isEmpty {
            let lineCount = max(1, summary.components(separatedBy: "\n").count)
            height += CGFloat(lineCount) * 18 + 8
        }

        if !parameters.isEmpty {
            height += 24
            for param in parameters {
                let descLines = max(1, param.description.components(separatedBy: "\n").count)
                height += 20 + CGFloat(descLines) * 16 + 6
            }
        }

        if let returns, !returns.isEmpty {
            height += 24
            let descLines = max(1, returns.components(separatedBy: "\n").count)
            height += CGFloat(descLines) * 16 + 6
        }

        if let throwsDescription, !throwsDescription.isEmpty {
            height += 24
            let descLines = max(1, throwsDescription.components(separatedBy: "\n").count)
            height += CGFloat(descLines) * 16 + 6
        }

        for callout in callouts {
            let msgLines = max(1, callout.message.components(separatedBy: "\n").count)
            height += 24 + CGFloat(msgLines) * 16 + 8
        }

        if let discussion, !discussion.isEmpty {
            let discLines = max(1, discussion.components(separatedBy: "\n").count)
            height += CGFloat(discLines) * 16 + 10
        }

        return height
    }
}

/// A parsed code declaration with smart line-breaking formatting.
struct LSPHoverDeclaration: Equatable {
    /// Classification of the symbol declaration (e.g. Function, Variable, Structure).
    enum SymbolKind: String, Equatable {
        case function = "Function"
        case method = "Method"
        case variable = "Variable"
        case constant = "Constant"
        case property = "Property"
        case `struct` = "Structure"
        case `class` = "Class"
        case `enum` = "Enumeration"
        case `protocol` = "Protocol"
        case typeAlias = "Type Alias"
        case initializer = "Initializer"
        case subscriptSymbol = "Subscript"
        case macro = "Macro"
        case namespace = "Namespace"

        var iconName: String {
            switch self {
            case .function, .method: return "function"
            case .variable, .property: return "shippingbox"
            case .constant: return "lock"
            case .struct: return "square.3.layers.3d.down.right"
            case .class: return "cube.fill"
            case .enum: return "list.bullet.rectangle"
            case .protocol: return "point.3.connected.trianglepath.dotted"
            case .typeAlias: return "character.cursor.ibeam"
            case .initializer: return "hammer"
            case .subscriptSymbol: return "arrow.down.right.and.arrow.up.left"
            case .macro: return "number"
            case .namespace: return "shippingbox.and.arrow.backward"
            }
        }

        var tintColor: SwiftUI.Color {
            switch self {
            case .function, .method: return .purple
            case .variable, .property: return .cyan
            case .constant: return .blue
            case .struct, .class, .enum, .typeAlias: return .orange
            case .protocol: return .indigo
            case .initializer, .subscriptSymbol: return .purple
            case .macro: return .brown
            case .namespace: return .green
            }
        }

        var title: String { rawValue }
    }

    /// The formatted code string ready for display.
    var code: String

    /// The raw original code declaration.
    var rawCode: String

    /// The programming language tag (e.g. "swift", "cpp", "python"), if known.
    var language: String?

    /// The extracted symbol name (e.g. "calculateTotal", "username"), if detected.
    var symbolName: String?

    /// The symbol classification kind.
    var kind: SymbolKind?

    init(
        code: String,
        rawCode: String,
        language: String? = nil,
        symbolName: String? = nil,
        kind: SymbolKind? = nil
    ) {
        self.code = code
        self.rawCode = rawCode
        self.language = language
        self.symbolName = symbolName
        self.kind = kind ?? Self.detectKind(rawCode: rawCode)
    }

    /// Automatically classifies the declaration kind from its raw code string.
    static func detectKind(rawCode: String) -> SymbolKind? {
        let trimmed = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let special = detectSpecialKind(trimmed) { return special }
        if let typeKind = detectTypeKind(trimmed) { return typeKind }
        return detectValueOrFuncKind(trimmed)
    }

    private static func detectSpecialKind(_ trimmed: String) -> SymbolKind? {
        if trimmed.contains("init(") || trimmed.contains("init<") || trimmed.contains("init?(") {
            return .initializer
        }
        if trimmed.contains("subscript(") || trimmed.contains("subscript<") {
            return .subscriptSymbol
        }
        if trimmed.contains("namespace ") { return .namespace }
        if trimmed.hasPrefix("#define") { return .macro }
        return nil
    }

    private static func detectTypeKind(_ trimmed: String) -> SymbolKind? {
        if trimmed.contains("struct ") { return .struct }
        if trimmed.contains("class ") { return .class }
        if trimmed.contains("enum ") { return .enum }
        if trimmed.contains("protocol ") || trimmed.contains("interface ") || trimmed.contains("trait ") {
            return .protocol
        }
        if trimmed.contains("typealias ") || trimmed.contains("typedef ") || trimmed.contains("using ") {
            return .typeAlias
        }
        return nil
    }

    private static func detectValueOrFuncKind(_ trimmed: String) -> SymbolKind? {
        if trimmed.hasPrefix("let ") || trimmed.contains(" let ") || trimmed.contains("const ")
            || trimmed.contains("constexpr ") || trimmed.contains("consteval ") {
            return .constant
        }
        if trimmed.contains("func ") || trimmed.contains("def ") || trimmed.contains("fn ")
            || trimmed.contains("pub fn ") || trimmed.contains("operator") {
            return .function
        }
        if trimmed.hasPrefix("var ") || trimmed.contains(" var ") || trimmed.contains("(variable)")
            || trimmed.contains("mut ") {
            return .variable
        }
        if trimmed.contains("(") && trimmed.contains(")") {
            return .function
        }
        if trimmed.contains(":") || trimmed.contains("=") {
            return .variable
        }
        return nil
    }
}

/// A single parameter in the documentation.
struct LSPHoverParameter: Identifiable, Equatable {
    /// Unique identifier for SwiftUI lists.
    var id: UUID

    /// Parameter identifier name (e.g. "count", "handler").
    var name: String

    /// Optional type annotation (e.g. "Int", "list[str]").
    var type: String?

    /// Description text for this parameter.
    var description: String

    init(id: UUID = UUID(), name: String, type: String? = nil, description: String) {
        self.id = id
        self.name = name
        self.type = type
        self.description = description
    }

    static func == (lhs: LSPHoverParameter, rhs: LSPHoverParameter) -> Bool {
        lhs.name == rhs.name && lhs.type == rhs.type && lhs.description == rhs.description
    }
}

/// A callout notice within the documentation.
struct LSPHoverCallout: Identifiable, Equatable {
    /// Callout classification.
    enum Kind: String, Equatable {
        case note
        case warning
        case important
        case deprecated
        case seeAlso
    }

    /// Unique identifier for SwiftUI lists.
    var id: UUID

    /// Kind of callout.
    var kind: Kind

    /// Title label for the callout (e.g. "Note", "Warning").
    var title: String

    /// Body message for the callout.
    var message: String

    init(id: UUID = UUID(), kind: Kind, title: String, message: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
    }

    static func == (lhs: LSPHoverCallout, rhs: LSPHoverCallout) -> Bool {
        lhs.kind == rhs.kind && lhs.title == rhs.title && lhs.message == rhs.message
    }

    /// SF Symbol icon name appropriate for this callout.
    var iconName: String {
        switch kind {
        case .note:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .important:
            return "exclamationmark.circle.fill"
        case .deprecated:
            return "exclamationmark.octagon.fill"
        case .seeAlso:
            return "link"
        }
    }

    /// Color tint for this callout card.
    var tintColor: SwiftUI.Color {
        switch kind {
        case .note:
            return .blue
        case .warning:
            return .orange
        case .important:
            return .purple
        case .deprecated:
            return .red
        case .seeAlso:
            return .teal
        }
    }
}
