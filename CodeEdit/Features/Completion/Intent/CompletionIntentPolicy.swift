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

    /// The intents in which plain words from the document are offered. In CMake's arguments and
    /// references they are the project's own targets and variables.
    static let documentWordIntents: Set<CompletionIntent> = [
        .expression, .statement, .unknown, .topLevel, .typeName, .argument, .variableReference
    ]

    /// The weight of a document word where it is offered: low, so any real symbol outranks it.
    static let documentWordWeight = 0.25

    /// The weight of a postfix template after `.`: below the members the server offers there.
    static let postfixWeight = 0.6

    /// The weight of a candidate of `kind` from `source` for `intent`, or `nil` to exclude it.
    ///
    /// `languageId` matters for ``CompletionIntent/statement`` and ``CompletionIntent/topLevel``,
    /// which mean "a declaration or statement" in the C family and Dart but "a command name" in CMake,
    /// and for ``CompletionIntent/argument`` and ``CompletionIntent/variableReference``, which mean a
    /// call's arguments and an interpolated name in Dart but a command's arguments and a `${…}` name in
    /// CMake. `isNamedArgument` marks a server item that fills a named argument (`padding: `), which
    /// leads a Dart argument list.
    static func weight(
        kind: LSPCompletionCategory,
        source: CompletionSource,
        intent: CompletionIntent,
        isExplicit: Bool,
        languageId: String = "",
        isNamedArgument: Bool = false
    ) -> Double? {
        if source == .word {
            return documentWordIntents.contains(intent) ? documentWordWeight : nil
        }
        if source == .postfix {
            return intent == .memberAccess ? postfixWeight : nil
        }
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
        case .statement, .topLevel:
            return blockWeight(kind: kind, intent: intent, languageId: languageId)
        case .variableReference, .argument:
            return referenceOrArgumentWeight(
                kind: kind,
                intent: intent,
                languageId: languageId,
                isNamedArgument: isNamedArgument
            )
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

    /// Weights where a statement or declaration starts: a function body or file scope. In CMake it is
    /// the start of a command.
    private static func blockWeight(
        kind: LSPCompletionCategory,
        intent: CompletionIntent,
        languageId: String
    ) -> Double {
        if CMakeKeywords.languageIds.contains(languageId) {
            return commandNameWeight(kind: kind)
        }
        if intent == .statement {
            return statementWeight(kind: kind)
        }
        return typeKinds.union([.snippet]).contains(kind) ? 1.0 : (kind == .keyword ? 0.9 : 0.4)
    }

    private static func statementWeight(kind: LSPCompletionCategory) -> Double {
        if kind == .snippet || kind == .keyword { return 1.0 }
        if valueKinds.contains(kind) { return 0.8 }
        return typeKinds.contains(kind) || kind == .namespace ? 0.6 : 0.4
    }

    /// Weights for the two intents only CMake and Dart produce.
    private static func referenceOrArgumentWeight(
        kind: LSPCompletionCategory,
        intent: CompletionIntent,
        languageId: String,
        isNamedArgument: Bool
    ) -> Double? {
        guard DartKeywords.languageIds.contains(languageId) else {
            return cmakeWeight(kind: kind, intent: intent)
        }
        guard kind != .snippet else { return nil }
        return intent == .argument
            ? dartArgumentWeight(kind: kind, isNamedArgument: isNamedArgument)
            : dartInterpolationWeight(kind: kind)
    }

    // MARK: - CMake

    /// Weights at the start of a CMake command. The server sends commands as functions; the local
    /// tables send the same names (merged with the server's by the deduplicator) and snippets.
    /// Variables, targets, and modules do not start a command.
    private static func commandNameWeight(kind: LSPCompletionCategory) -> Double {
        switch kind {
        case .function: return 1.0
        case .snippet: return 0.95
        case .keyword: return 0.9
        default: return 0.2
        }
    }

    /// Weights for the two intents only CMake produces.
    private static func cmakeWeight(kind: LSPCompletionCategory, intent: CompletionIntent) -> Double? {
        if intent == .variableReference {
            return variableReferenceWeight(kind: kind)
        }
        return kind == .snippet ? nil : argumentWeight(kind: kind)
    }

    /// Weights inside `${…}`: a variable, nothing the user would write as a command or keyword.
    /// Constants such as `ON` and the server's built-in values (`macro`) follow variables.
    private static func variableReferenceWeight(kind: LSPCompletionCategory) -> Double? {
        switch kind {
        case .snippet, .keyword: return nil
        case .variable: return 1.0
        case .macro, .enumMember: return 0.9
        case .namespace, .file, .folder: return 0.3
        default: return 0.2
        }
    }

    /// Weights in a command's arguments, where nearly anything goes. Keyword arguments are common
    /// but rank below a symbol the user is clearly spelling, until an `ALL_CAPS` prefix says
    /// otherwise (see ``prefixShapeBonus(kind:prefix:intent:)``). Modules and files cover
    /// `find_package(` and `include(`.
    private static func argumentWeight(kind: LSPCompletionCategory) -> Double {
        switch kind {
        case .variable: return 0.9
        case .namespace, .file: return 0.8
        case .keyword, .macro, .enumMember: return 0.8
        case .folder: return 0.7
        case .function: return 0.5
        default: return 0.3
        }
    }

    // MARK: - Dart

    /// Whether `label` is a Dart named argument as the analysis server labels it: `padding: `.
    static func isNamedArgumentLabel(_ label: String) -> Bool {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 1, trimmed.hasSuffix(":"), !trimmed.hasSuffix("::") else { return false }
        return !trimmed.dropLast().contains(where: \.isWhitespace)
    }

    /// Weights in a Dart call's arguments (snippets are excluded before). The named arguments the callee
    /// still accepts (`child: `, `padding: `) lead, followed by values for a positional argument.
    private static func dartArgumentWeight(kind: LSPCompletionCategory, isNamedArgument: Bool) -> Double {
        if isNamedArgument { return 1.0 }
        switch kind {
        case .variable, .function, .enumMember, .macro: return 0.6
        case .keyword: return 0.5
        default: return typeKinds.contains(kind) ? 0.5 : 0.3
        }
    }

    /// Weights for a name interpolated into a Dart string, `'$…'` or `'${…}'` (snippets are excluded
    /// before). A variable is what the user wants; a getter or function call (`${f()}`) follows, keywords
    /// and types trail.
    private static func dartInterpolationWeight(kind: LSPCompletionCategory) -> Double {
        switch kind {
        case .variable: return 1.0
        case .enumMember, .macro: return 0.8
        case .function: return 0.6
        case .keyword: return 0.4
        default: return 0.3
        }
    }

    // MARK: - Prefix shape

    /// A bonus for candidates whose kind matches the shape of what the user typed: an `ALL_CAPS`
    /// prefix is looking for a macro or constant, a `Capitalized` prefix for a type. In a CMake
    /// command's arguments (`intent` is ``CompletionIntent/argument``), an `ALL_CAPS` prefix is a
    /// keyword argument (`PUB` for `PUBLIC`), so keywords get the bonus too.
    static func prefixShapeBonus(
        kind: LSPCompletionCategory,
        prefix: String,
        intent: CompletionIntent? = nil
    ) -> Double {
        let letters = prefix.filter(\.isLetter)
        guard letters.count >= 2, let first = letters.first else { return 0 }
        if letters.allSatisfy(\.isUppercase) {
            if intent == .argument && kind == .keyword { return 0.3 }
            return kind == .macro || kind == .enumMember ? 0.3 : 0
        }
        if first.isUppercase {
            return typeKinds.contains(kind) || kind == .namespace ? 0.2 : 0
        }
        return 0
    }
}
