//
//  CFamilyKeywords.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/30/26.
//

/// C and C++ keyword groups used to recognize completion intent from the tokens before the cursor.
enum CFamilyKeywords {
    /// Language identifiers the C-family token rules apply to.
    static let languageIds: Set<String> = ["c", "cpp", "objective-c", "objective-cpp"]
    /// Languages where an identifier followed by a space starts a declaration (`Point p`). Excludes
    /// Objective-C, where `[receiver message` has the same shape.
    static let identifierDeclarationLanguageIds: Set<String> = ["c", "cpp"]

    /// Keywords after which only a value can follow.
    static let expressionLeads: Set<String> = [
        "return", "throw", "co_return", "co_yield", "co_await", "delete", "sizeof", "alignof",
        "and", "or", "not", "xor", "bitand", "bitor", "compl", "not_eq", "and_eq", "or_eq", "xor_eq"
    ]

    /// The intent after a keyword and a space, for keywords that fully decide it.
    static let intentAfterKeyword: [String: CompletionIntent] = {
        var intents: [String: CompletionIntent] = ["case": .caseLabel, "else": .statement, "do": .statement]
        for keyword in expressionLeads {
            intents[keyword] = .expression
        }
        return intents
    }()

    /// The intent right after `keyword(`, for keywords whose parentheses are not a call.
    static let intentInsideParens: [String: CompletionIntent] = [
        "if": .expression, "while": .expression, "switch": .expression,
        "for": .statement, "catch": .typeName,
        "sizeof": .expression, "alignof": .expression, "alignas": .expression, "decltype": .expression,
        "typeid": .expression, "noexcept": .expression, "static_assert": .expression
    ]

    /// Specifiers and qualifiers after which a type is expected.
    static let typeModifiers: Set<String> = [
        "const", "volatile", "unsigned", "signed", "long", "short", "static", "extern", "inline",
        "constexpr", "consteval", "constinit", "virtual", "friend", "typedef", "typename", "mutable",
        "register", "thread_local", "explicit", "new", "struct", "class", "union", "enum",
        "public", "private", "protected", "_Atomic", "restrict"
    ]

    /// Complete built-in types, after which a declarator name follows.
    static let builtinTypes: Set<String> = [
        "void", "bool", "_Bool", "char", "wchar_t", "char8_t", "char16_t", "char32_t", "int", "float",
        "double", "auto", "size_t", "ssize_t", "ptrdiff_t", "intptr_t", "uintptr_t", "int8_t",
        "int16_t", "int32_t", "int64_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t"
    ]

    /// Keywords that cannot appear inside a type.
    static let nonTypeKeywords: Set<String> = expressionLeads.union([
        "case", "default", "goto", "if", "else", "for", "while", "do", "switch", "break", "continue",
        "try", "catch", "this", "true", "false", "nullptr", "template", "using", "namespace",
        "operator", "static_assert", "new", "NULL"
    ])

    /// Tokens that end the previous declaration or argument, so a new type may start after them.
    static let segmentBoundaries: Set<String> = [";", "}", ",", "=", "?", ":"]

    /// Whether `word` is a keyword rather than a user identifier.
    static func isReserved(_ word: String) -> Bool {
        nonTypeKeywords.contains(word) || typeModifiers.contains(word) || builtinTypes.contains(word)
    }

    /// Whether `word` looks like a macro (`EXPORT_API`), which often precedes a declaration without
    /// being a type.
    static func isMacroLike(_ word: String) -> Bool {
        word.count >= 2
            && word.contains(where: \.isLetter)
            && word.allSatisfy { $0.isUppercase || $0.isNumber || $0 == "_" }
    }
}
