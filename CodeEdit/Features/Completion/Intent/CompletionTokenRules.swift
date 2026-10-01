//
//  CompletionTokenRules.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/30/26.
//

/// The token rules of ``CompletionIntentRecognizer``: what the tokens typed before the prefix on
/// the cursor's line say about the user's intent.
///
/// Each rule returns `nil` when the tokens are inconclusive, so the recognizer can fall back to the
/// enclosing scope from the syntax tree.
enum CompletionTokenRules {
    typealias Token = CompletionLineScanner.Token

    /// The tokens to classify, plus the facts about the surrounding code the rules need.
    struct Input {
        /// The complete tokens before the prefix.
        let tokens: [Token]
        /// Whether whitespace separates the last token from the prefix.
        let hasTrailingSpace: Bool
        /// Whether the cursor is inside a function body, where `Foo f(` is a constructor call rather
        /// than a function declaration.
        let isInFunctionBody: Bool
        /// Whether the language is C or C++. Objective-C is excluded from the "identifier followed by
        /// a name" rule, since `[receiver message` has the same shape.
        let allowsIdentifierDeclarations: Bool
    }

    /// Operator tokens that can only be followed by a value.
    private static let expressionOperators: Set<String> = [
        "=", "==", "!=", "<=", ">=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>=",
        "+", "-", "/", "%", "^", "|", "||", "!", "~", "?", "[", "<<"
    ]

    /// The intent after the language-neutral access operators, or `nil` if the last token is not one.
    static func accessIntent(for tokens: [Token]) -> CompletionIntent? {
        switch tokens.last?.text {
        case ".", "->": return .memberAccess
        case "::": return .scopeAccess
        default: return nil
        }
    }

    /// The intent the C-family token rules recognize, or `nil` when they are inconclusive.
    static func intent(for input: Input) -> CompletionIntent? {
        guard let last = input.tokens.last else { return nil }
        if let intent = accessIntent(for: input.tokens) {
            return intent
        }
        switch last.kind {
        case .word:
            return input.hasTrailingSpace ? intent(afterWord: last.text, input: input) : nil
        case .punctuation:
            return intent(afterPunctuation: last, input: input)
        case .number, .literal:
            return nil
        }
    }

    // MARK: - After a word

    private static func intent(afterWord word: String, input: Input) -> CompletionIntent? {
        if let intent = CFamilyKeywords.intentAfterKeyword[word] {
            return intent
        }
        if word == "namespace" {
            let previous = input.tokens.dropLast().last?.text
            return previous == "using" ? .typeName : .declarationName
        }
        if CFamilyKeywords.typeModifiers.contains(word) {
            return .typeName
        }
        if CFamilyKeywords.builtinTypes.contains(word) {
            return .declarationName
        }
        // `Point p`, `std::string name`: an identifier used as a type, then a new name.
        if input.allowsIdentifierDeclarations,
           !CFamilyKeywords.isReserved(word),
           !CFamilyKeywords.isMacroLike(word),
           startsDeclaration(input.tokens, input: input) {
            return .declarationName
        }
        return nil
    }

    // MARK: - After punctuation

    private static func intent(afterPunctuation last: Token, input: Input) -> CompletionIntent? {
        let tokens = input.tokens
        switch last.text {
        case "<":
            return intentAfterOpeningAngle(last, before: tokens.dropLast().last)
        case ">", ">>":
            return intentAfterClosingAngle(input)
        case "*", "&", "&&":
            return startsDeclaration(Array(tokens.dropLast()), input: input) ? .declarationName : .expression
        case "(":
            return intentAfterOpeningParen(at: tokens.count - 1, input: input)
        case ",":
            return intentAfterComma(input)
        case "{":
            return intentAfterOpeningBrace(tokens)
        case ":":
            return intentAfterSingleColon(tokens)
        default:
            return expressionOperators.contains(last.text) ? .expression : nil
        }
    }

    /// `vector<`, `static_cast<`, `template <` expect a type; a spaced `a < ` is a comparison.
    private static func intentAfterOpeningAngle(_ angle: Token, before: Token?) -> CompletionIntent {
        guard let before, before.kind == .word else { return .expression }
        return before.text == "template" || !angle.hasLeadingSpace ? .typeName : .expression
    }

    /// A `>` that closes a template argument list ends a type; otherwise it is a comparison.
    private static func intentAfterClosingAngle(_ input: Input) -> CompletionIntent? {
        let tokens = input.tokens
        guard tokens.contains(where: { $0.text == "<" }), angleBalance(tokens[...]) == 0 else {
            return .expression
        }
        if tokens.first?.text == "template" {
            // `template <typename T> |`: the templated declaration follows.
            return .topLevel
        }
        return input.hasTrailingSpace && startsDeclaration(tokens, input: input) ? .declarationName : nil
    }

    private static func intentAfterOpeningParen(at index: Int, input: Input) -> CompletionIntent {
        let before = input.tokens[..<index]
        if let word = before.last, word.kind == .word, let intent = CFamilyKeywords.intentInsideParens[word.text] {
            return intent
        }
        return isParameterList(openingAt: index, input: input) ? .typeName : .expression
    }

    private static func intentAfterComma(_ input: Input) -> CompletionIntent {
        let tokens = input.tokens
        guard let open = enclosingOpenBracket(in: tokens, before: tokens.count - 1) else {
            // `int a, b`: another declarator of the same declaration.
            let segment = currentSegment(Array(tokens.dropLast()))
            return segment.boundary == nil && isTypePhrase(segment.tokens.dropLast(1)) ? .declarationName : .expression
        }
        switch tokens[open].text {
        case "<":
            return .typeName
        case "(":
            return isParameterList(openingAt: open, input: input) ? .typeName : .expression
        case "{":
            return tokens[..<open].contains { $0.text == "enum" } ? .declarationName : .expression
        default:
            return .expression
        }
    }

    private static func intentAfterOpeningBrace(_ tokens: [Token]) -> CompletionIntent? {
        let before = tokens.dropLast()
        if before.contains(where: { $0.text == "enum" }) {
            return .declarationName
        }
        return before.last?.text == "=" || before.last?.text == "(" || before.last?.text == "," ? .expression : nil
    }

    private static func intentAfterSingleColon(_ tokens: [Token]) -> CompletionIntent? {
        if tokens.contains(where: { $0.text == "?" }) {
            return .expression
        }
        // `class Derived : public Base` / `struct S : Base`.
        if let first = tokens.first?.text, first == "class" || first == "struct" {
            return .typeName
        }
        return nil
    }

    // MARK: - Declarations

    /// Whether `tokens` end with a type that starts a declaration: the tokens since the last
    /// statement or parameter boundary form a type, and that boundary allows a declaration.
    private static func startsDeclaration(_ tokens: [Token], input: Input) -> Bool {
        let segment = currentSegment(tokens)
        guard isTypePhrase(segment.tokens[...]) else { return false }
        guard let boundary = segment.boundary else { return true }
        switch tokens[boundary].text {
        case ";", "{", "}", "<", ":":
            return true
        case "(":
            let before = tokens[..<boundary].last?.text
            return before == "for" || before == "catch" || isParameterList(openingAt: boundary, input: input)
        case ",":
            guard let open = enclosingOpenBracket(in: tokens, before: boundary) else { return true }
            return tokens[open].text == "<" || isParameterList(openingAt: open, input: input)
        default:
            return false
        }
    }

    /// Whether the `(` at `index` opens a function declaration's parameter list: `void f(`,
    /// `int *make(`, `void Foo::bar(`. A call such as `foo(` or `std::max(` has no type before its
    /// name. Inside a function body `Foo f(` is treated as a constructor call.
    private static func isParameterList(openingAt index: Int, input: Input) -> Bool {
        guard !input.isInFunctionBody else { return false }
        var nameStart = index
        // Strip the (possibly qualified) name: `bar`, `Foo::bar`.
        while nameStart > 0, input.tokens[nameStart - 1].kind == .word {
            nameStart -= 1
            guard nameStart > 0, input.tokens[nameStart - 1].text == "::" else { break }
            nameStart -= 1
        }
        guard nameStart < index, input.tokens[nameStart].kind == .word else { return false }
        let segment = currentSegment(Array(input.tokens[..<nameStart]))
        let startsStatement = segment.boundary.map { [";", "{", "}", ":"].contains(input.tokens[$0].text) } ?? true
        return startsStatement && isTypePhrase(segment.tokens[...])
    }

    /// The tokens since the last declaration/statement boundary at bracket depth zero, and the index
    /// of that boundary token (`nil` when the segment starts the line).
    static func currentSegment(_ tokens: [Token]) -> (tokens: [Token], boundary: Int?) {
        var depth = 0
        var index = tokens.count
        while index > 0 {
            let text = tokens[index - 1].text
            switch text {
            case ")", "]", ">":
                depth += 1
            case ">>":
                depth += 2
            case "(", "[", "<", "{":
                if depth == 0 { return (Array(tokens[index...]), index - 1) }
                depth -= 1
            default:
                if depth == 0, CFamilyKeywords.segmentBoundaries.contains(text) {
                    return (Array(tokens[index...]), index - 1)
                }
            }
            index -= 1
        }
        return (tokens, nil)
    }

    /// Whether `tokens` read as a type: words that are not statement/expression keywords, joined by
    /// `::`, template arguments, `*`, and `&`.
    static func isTypePhrase(_ tokens: ArraySlice<Token>) -> Bool {
        guard let first = tokens.first, first.kind == .word || first.text == "::" else { return false }
        var angle = 0
        for token in tokens {
            switch token.kind {
            case .word:
                if CFamilyKeywords.nonTypeKeywords.contains(token.text) { return false }
            case .number:
                if angle == 0 { return false }
            case .literal:
                return false
            case .punctuation:
                guard isTypePunctuation(token.text, angle: &angle) else { return false }
            }
        }
        return angle == 0
    }

    private static func isTypePunctuation(_ text: String, angle: inout Int) -> Bool {
        switch text {
        case "::", "*", "&", "&&":
            return true
        case "<":
            angle += 1
            return true
        case ">", ">>":
            angle -= text.count
            return angle >= 0
        case ",":
            return angle > 0
        default:
            return false
        }
    }

    private static func angleBalance(_ tokens: ArraySlice<Token>) -> Int {
        tokens.reduce(0) { balance, token in
            switch token.text {
            case "<": return balance + 1
            case ">", ">>": return balance - token.text.count
            default: return balance
            }
        }
    }

    /// The index of the unclosed `(`, `<`, `[`, or `{` enclosing the token at `end`, if any.
    private static func enclosingOpenBracket(in tokens: [Token], before end: Int) -> Int? {
        var depth = 0
        var index = end
        while index > 0 {
            index -= 1
            switch tokens[index].text {
            case ")", "]", "}", ">":
                depth += 1
            case ">>":
                depth += 2
            case "(", "[", "{", "<":
                if depth == 0 { return index }
                depth -= 1
            default:
                break
            }
        }
        return nil
    }
}
