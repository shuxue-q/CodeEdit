//
//  CompletionIntentPolicy.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/30/26.
//

/// What each ``CompletionIntent`` means for the completion list: whether typing opens the window,
/// which candidates are excluded, and how the rest are weighted.
enum CompletionIntentPolicy {
    /// Type-like symbol kinds.
    static let typeKinds: Set<LSPCompletionCategory> = [.class, .struct, .interface, .enum, .typeAlias]
    /// Value-like symbol kinds.
    static let valueKinds: Set<LSPCompletionCategory> = [.variable, .function]

    /// Whether a typing-triggered request should open the window for `intent`.
    ///
    /// Inside comments, strings, and number literals, and while naming a new declaration, a popup
    /// only gets in the way. An explicit request always opens the window.
    static func allowsAutomaticCompletion(for intent: CompletionIntent) -> Bool {
        switch intent {
        case .comment, .string, .numberLiteral, .declarationName:
            return false
        default:
            return true
        }
    }

    /// The weight of a candidate of `kind` from `source` for `intent`, or `nil` to exclude it.
    static func weight(
        kind: LSPCompletionCategory,
        source: CompletionSource,
        intent: CompletionIntent,
        isExplicit: Bool
    ) -> Double? {
        switch intent {
        case .comment, .string, .numberLiteral, .declarationName:
            // Only reachable on an explicit request; offer everything at a low weight.
            return isExplicit ? 0.1 : nil
        case .memberAccess, .scopeAccess, .caseLabel, .includePath:
            return isLocalTemplate(source) ? nil : symbolWeight(kind: kind, intent: intent)
        case .preprocessor:
            return preprocessorWeight(kind: kind, source: source)
        case .typeName:
            return typeNameWeight(kind: kind)
        case .expression:
            return kind == .snippet ? nil : expressionWeight(kind: kind)
        case .statement:
            return statementWeight(kind: kind)
        case .topLevel:
            return typeKinds.union([.snippet]).contains(kind) ? 1.0 : (kind == .keyword ? 0.9 : 0.4)
        case .unknown:
            return 0.5
        }
    }

    /// Snippets and keywords from the static tables, as opposed to symbols from a server.
    private static func isLocalTemplate(_ source: CompletionSource) -> Bool {
        source == .snippet || source == .keyword
    }

    /// Weights for intents that complete an existing symbol: a member, a scoped name, a case label,
    /// or a header path.
    private static func symbolWeight(kind: LSPCompletionCategory, intent: CompletionIntent) -> Double {
        switch intent {
        case .memberAccess:
            return valueKinds.contains(kind) ? 1.0 : (kind == .enumMember ? 0.8 : 0.4)
        case .scopeAccess:
            if typeKinds.contains(kind) || kind == .namespace { return 1.0 }
            return valueKinds.contains(kind) || kind == .enumMember ? 0.9 : 0.4
        case .caseLabel:
            if kind == .enumMember { return 1.0 }
            if kind == .macro { return 0.9 }
            return typeKinds.contains(kind) || kind == .namespace ? 0.5 : 0.3
        default:
            return kind == .file || kind == .folder ? 1.0 : 0.2
        }
    }

    private static func preprocessorWeight(kind: LSPCompletionCategory, source: CompletionSource) -> Double? {
        guard ![.macro, .file, .snippet].contains(kind) else { return 1.0 }
        return source == .lsp ? 0.3 : nil
    }

    private static func typeNameWeight(kind: LSPCompletionCategory) -> Double {
        if typeKinds.contains(kind) || kind == .namespace { return 1.0 }
        switch kind {
        case .keyword: return 0.9
        case .snippet: return 0.6
        case .macro: return 0.4
        default: return 0.2
        }
    }

    private static func expressionWeight(kind: LSPCompletionCategory) -> Double {
        if valueKinds.contains(kind) { return 1.0 }
        switch kind {
        case .enumMember: return 0.9
        case .macro: return 0.8
        case .keyword: return 0.7
        default: return typeKinds.contains(kind) || kind == .namespace ? 0.5 : 0.4
        }
    }

    private static func statementWeight(kind: LSPCompletionCategory) -> Double {
        if kind == .snippet || kind == .keyword { return 1.0 }
        if valueKinds.contains(kind) { return 0.8 }
        return typeKinds.contains(kind) || kind == .namespace ? 0.6 : 0.4
    }

    // MARK: - Prefix shape

    /// A bonus for candidates whose kind matches the shape of what the user typed: an `ALL_CAPS`
    /// prefix is looking for a macro or constant, a `Capitalized` prefix for a type.
    static func prefixShapeBonus(kind: LSPCompletionCategory, prefix: String) -> Double {
        let letters = prefix.filter(\.isLetter)
        guard letters.count >= 2, let first = letters.first else { return 0 }
        if letters.allSatisfy(\.isUppercase) {
            return kind == .macro || kind == .enumMember ? 0.3 : 0
        }
        if first.isUppercase {
            return typeKinds.contains(kind) || kind == .namespace ? 0.2 : 0
        }
        return 0
    }
}
