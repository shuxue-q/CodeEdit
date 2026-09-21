//
//  LSPCompletionEntry.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/10/26.
//

import SwiftUI
import CodeEditSourceEditor
import LanguageServerProtocol

/// A single row in the code suggestion window, backed by an LSP ``CompletionItem``.
struct LSPCompletionEntry: CodeSuggestionEntry {
    /// Categories representing completion symbol kinds.
    enum Category: Equatable, Hashable, Sendable {
        case function
        case variable
        case `class`
        case `struct`
        case interface
        case `enum`
        case enumMember
        case macro
        case namespace
        case typeAlias
        case keyword
        case snippet
        case file
        case folder
        case text
        case color
        case reference
        case event
        case other
    }

    /// The original completion item, kept for applying the completion.
    let item: CompletionItem

    init(item: CompletionItem) {
        self.item = item
    }

    var label: String {
        let trimmed = item.label.trimmingCharacters(in: .whitespaces)
        if trimmed == "include" {
            if isAngleInclude {
                return "#include <insert>"
            } else if isQuoteInclude {
                return "#include \"insert\""
            }
        }
        return item.label
    }

    var detail: String? {
        if let detail = item.detail, !detail.isEmpty {
            return detail
        }
        let trimmed = item.label.trimmingCharacters(in: .whitespaces)
        if trimmed == "include" || trimmed.hasPrefix("#include") {
            if isAngleInclude {
                return "Include system header"
            } else if isQuoteInclude {
                return "Include user header"
            }
        }
        return item.detail
    }

    private var isAngleInclude: Bool {
        if item.label.contains("<") { return true }
        if let insertText = item.insertText, insertText.contains("<") { return true }
        if let textEdit = item.textEdit {
            switch textEdit {
            case .optionA(let edit): return edit.newText.contains("<")
            case .optionB(let edit): return edit.newText.contains("<")
            }
        }
        return false
    }

    private var isQuoteInclude: Bool {
        if item.label.contains("\"") { return true }
        if let insertText = item.insertText, insertText.contains("\"") { return true }
        if let textEdit = item.textEdit {
            switch textEdit {
            case .optionA(let edit): return edit.newText.contains("\"")
            case .optionB(let edit): return edit.newText.contains("\"")
            }
        }
        return false
    }

    var documentation: String? {
        switch item.documentation {
        case .optionA(let string):
            return string
        case .optionB(let markupContent):
            return markupContent.value
        case nil:
            return nil
        }
    }

    var pathComponents: [String]? { nil }
    var targetPosition: CursorPosition? { nil }
    var sourcePreview: String? { nil }

    var category: Category {
        Self.category(for: item)
    }

    var iconName: String {
        Self.imageName(for: item)
    }

    var image: Image {
        Image(systemName: iconName)
    }

    var imageColor: SwiftUI.Color {
        Self.color(for: item)
    }

    var deprecated: Bool {
        item.deprecated ?? false
    }

    // MARK: - Classification & Icons

    private static let kindCategories: [CompletionItemKind: Category] = [
        .text: .text,
        .method: .function,
        .function: .function,
        .constructor: .function,
        .field: .variable,
        .variable: .variable,
        .class: .class,
        .interface: .interface,
        .module: .namespace,
        .property: .variable,
        .unit: .macro,
        .value: .macro,
        .enum: .enum,
        .keyword: .keyword,
        .snippet: .snippet,
        .color: .color,
        .file: .file,
        .reference: .reference,
        .folder: .folder,
        .enumMember: .enumMember,
        .constant: .macro,
        .struct: .struct,
        .event: .event,
        .operator: .keyword,
        .typeParameter: .typeAlias
    ]

    private static let categoryIconNames: [Category: String] = [
        .function: "function",
        .variable: "shippingbox",
        .class: "cube.fill",
        .struct: "square.3.layers.3d.down.right",
        .interface: "point.3.connected.trianglepath.dotted",
        .typeAlias: "character.cursor.ibeam",
        .enum: "list.bullet.rectangle",
        .enumMember: "numbersign",
        .macro: "number",
        .namespace: "shippingbox.and.arrow.backward",
        .keyword: "key",
        .snippet: "chevron.left.forwardslash.chevron.right",
        .file: "doc.text",
        .folder: "folder",
        .text: "text.alignleft",
        .color: "paintpalette",
        .reference: "link",
        .event: "bolt",
        .other: "cube"
    ]

    private static let categoryColors: [Category: SwiftUI.Color] = [
        .function: .purple,
        .variable: .cyan,
        .class: .orange,
        .struct: .orange,
        .typeAlias: .orange,
        .enum: .orange,
        .interface: .indigo,
        .enumMember: .yellow,
        .macro: .brown,
        .namespace: .green,
        .keyword: .pink,
        .snippet: .secondary,
        .file: .secondary,
        .folder: .secondary,
        .text: .secondary,
        .color: .cyan,
        .reference: .secondary,
        .event: .yellow,
        .other: .secondary
    ]

    private static let typeAliasKeywords = ["typedef", "using", "alias"]
    private static let typeAliasPrefixes = ["typedef ", "using ", "typealias "]

    private static func isTypeAlias(item: CompletionItem) -> Bool {
        if let detail = item.detail?.lowercased() {
            if detail.contains("concept") {
                return false
            }
            if typeAliasKeywords.contains(where: { detail.contains($0) }) {
                return true
            }
        }
        let label = item.label.lowercased()
        return typeAliasPrefixes.contains(where: { label.hasPrefix($0) })
    }

    /// Determines the symbol category for a given completion item.
    static func category(for item: CompletionItem) -> Category {
        let trimmed = item.label.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") {
            if trimmed == "#include" || trimmed.hasPrefix("#include") {
                return .snippet
            }
            return .macro
        }
        if trimmed == "include" || trimmed.hasPrefix("include") {
            return .snippet
        }
        guard let kind = item.kind else { return .other }
        if kind == .interface {
            return isTypeAlias(item: item) ? .typeAlias : .interface
        }
        return kindCategories[kind] ?? .other
    }

    /// The SF Symbol name used to represent a completion item.
    static func imageName(for item: CompletionItem) -> String {
        imageName(for: category(for: item))
    }

    /// The SF Symbol name used to represent a completion category.
    static func imageName(for category: Category) -> String {
        categoryIconNames[category] ?? "cube"
    }

    /// The tint color used for a completion item's icon.
    static func color(for item: CompletionItem) -> SwiftUI.Color {
        color(for: category(for: item))
    }

    /// The tint color used for a completion category's icon.
    static func color(for category: Category) -> SwiftUI.Color {
        categoryColors[category] ?? .secondary
    }
}

typealias LSPCompletionCategory = LSPCompletionEntry.Category
