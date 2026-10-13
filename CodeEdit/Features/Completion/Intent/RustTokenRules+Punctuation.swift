//
//  RustTokenRules+Punctuation.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/13/26.
//

/// The intent after an operator or bracket, and the bracket structure of the line around the cursor.
extension RustTokenRules {
    /// Operators and punctuation that fully decide the intent.
    private static let intentAfterOperator: [String: CompletionIntent] = {
        var intents: [String: CompletionIntent] = [
            ".": .memberAccess, "::": .scopeAccess, "::<": .typeName, "->": .typeName, "'": .typeName
        ]
        let valueOperators = [
            "==", "!=", "<=", ">=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>=", "&&", "||",
            "-", "*", "/", "%", "^", "<<", "..", "..=", "...", "[", "=>", "@"
        ]
        for text in valueOperators {
            intents[text] = .expression
        }
        return intents
    }()

    static func intent(afterPunctuation last: Token, input: Input) -> CompletionIntent? {
        if let intent = intentAfterOperator[last.text] {
            return intent
        }
        let tokens = input.tokens
        switch last.text {
        case "<":
            let before = tokens.dropLast().last
            return before?.kind == .word && !last.hasLeadingSpace ? .typeName : .expression
        case ">", ">>":
            return intentAfterClosingAngle(input)
        case "(":
            return intentInsideParens(openingAt: tokens.count - 1, input: input)
        case ",":
            return intentAfterComma(input)
        case ":":
            return intentAfterColon(input)
        case "{":
            return intentInsideBrace(openingAt: tokens.count - 1, tokens: tokens)
        default:
            return intent(afterOperator: last, input: input)
        }
    }

    /// `&`, `|`, `+`, `=`, and `!`, whose meaning depends on what precedes them.
    private static func intent(afterOperator last: Token, input: Input) -> CompletionIntent? {
        let tokens = input.tokens
        let before = tokens.dropLast().last?.text
        switch last.text {
        case "&":
            return intentAfterReference(input.ending(before: tokens.count - 1))
        case "|":
            // The pipe that opens a closure's parameters; any other `|` is an operator or ends the parameters.
            let opensClosure = before == nil || ["(", ",", "=", "=>", "{", ";", "[", "move", "return"].contains(before)
            return opensClosure ? .declarationName : .expression
        case "+":
            return isInTypeBounds(input) ? .typeName : .expression
        case "=":
            // `type Alias = |` names a type.
            return statementHead(tokens).contains("type") ? .typeName : .expression
        case "!":
            return before == "macro_rules" ? .declarationName : .expression
        default:
            return nil
        }
    }

    /// After `&` (or `&mut`), whatever the position before it expects: a type after `x: &`, `-> &`, `<&`,
    /// a parameter after `fn f(&`, and a value otherwise.
    /// - Parameter input: The input ending just before the `&`.
    static func intentAfterReference(_ input: Input) -> CompletionIntent {
        guard !input.tokens.isEmpty else { return .expression }
        switch intent(for: input) {
        case .typeName:
            return .typeName
        case .declarationName:
            return .declarationName
        default:
            return .expression
        }
    }

    // MARK: - Brackets

    /// A `>` that closes generics: `impl<T> |` is followed by the implemented type; after other closed
    /// generics the line is inconclusive. Without an open `<` it is a comparison.
    private static func intentAfterClosingAngle(_ input: Input) -> CompletionIntent? {
        let tokens = input.tokens
        guard let open = matchingAngle(closingAt: tokens.count - 1, in: tokens) else {
            return .expression
        }
        guard input.hasTrailingSpace else { return nil }
        return open > 0 && tokens[open - 1].text == "impl" ? .typeName : nil
    }

    /// The parentheses that open at `index`: a function's parameter list (a parameter name follows), or a
    /// call's, a macro's, a tuple's, or a condition's (a value follows).
    private static func intentInsideParens(openingAt index: Int, input: Input) -> CompletionIntent {
        isParameterList(openingAt: index, in: input.tokens) ? .declarationName : .expression
    }

    private static func intentAfterComma(_ input: Input) -> CompletionIntent? {
        let tokens = input.tokens
        if isInClosureParameters(input) {
            return .declarationName
        }
        guard let open = enclosingOpenBracket(in: tokens, before: tokens.count - 1) else {
            // `where T: Clone, |`. A comma ending a line of a multi-line list is left to the syntax tree.
            return statementHead(tokens).contains("where") ? .typeName : nil
        }
        switch tokens[open].text {
        case "<", "::<":
            return .typeName
        case "(":
            return intentInsideParens(openingAt: open, input: input)
        case "{":
            let inside = intentInsideBrace(openingAt: open, tokens: tokens)
            return inside == .statement || inside == .topLevel ? nil : inside
        default:
            return .expression
        }
    }

    /// `x: |` names a type in a binding, a parameter, a field declaration, a bound, or a constant, and a
    /// value in a struct literal (`Point { x: |`).
    private static func intentAfterColon(_ input: Input) -> CompletionIntent {
        let tokens = input.tokens
        if isInClosureParameters(input) {
            return .typeName
        }
        if let open = enclosingOpenBracket(in: tokens, before: tokens.count - 1) {
            switch tokens[open].text {
            case "<", "::<":
                return .typeName
            case "(":
                return isParameterList(openingAt: open, in: tokens) ? .typeName : .expression
            case "[":
                return .expression
            default:
                switch intentInsideBrace(openingAt: open, tokens: tokens) {
                case .declarationName: return .typeName
                case .expression: return .expression
                default: break
                }
            }
        }
        let head = statementHead(tokens)
        if ["let", "const", "static", "where"].contains(where: head.contains) {
            return .typeName
        }
        // A field on its own line: the tree says whether it is declared (`struct`) or initialized.
        return input.scope == .expression ? .expression : .typeName
    }

    /// What goes inside the `{` at `index`: field or variant names in a `struct`, `union`, or `enum` body,
    /// items in an `impl`, `trait`, `mod`, or `extern` body, values in a struct literal or `match`, and
    /// statements in any other block.
    static func intentInsideBrace(openingAt index: Int, tokens: [Token]) -> CompletionIntent {
        let head = braceHead(before: index, in: tokens)
        if head.contains(where: ["struct", "union", "enum"].contains) {
            return .declarationName
        }
        if head.contains("match") {
            return .expression
        }
        if !head.contains("fn") && head.contains(where: ["impl", "trait", "mod", "extern"].contains) {
            return .topLevel
        }
        if head.contains(where: RustKeywords.blockKeywords.contains) {
            return .statement
        }
        // `Point {`, `Wrapper::<T> {`: a struct literal.
        guard index > 0 else { return .statement }
        let before = tokens[index - 1]
        return before.kind == .word || before.text == ">" ? .expression : .statement
    }

    /// The words of the expression or item a `{` at `index` belongs to, nearest first: back to the nearest
    /// `;`, `{`, `}`, `=`, `=>`, `(`, `[`, or `,` outside parentheses, leaving out words inside them.
    /// `let p = Point {` gives `Point`; `fn f(a: A) -> B {` gives `B f fn`; `if a == b {` gives `b a if`.
    private static func braceHead(before index: Int, in tokens: [Token]) -> [String] {
        var words: [String] = []
        var depth = 0
        var cursor = index - 1
        while cursor >= 0 {
            let token = tokens[cursor]
            switch token.text {
            case ")", "]":
                depth += 1
            case "(", "[":
                if depth == 0 { return words }
                depth -= 1
            case ";", "{", "}", "=", "=>", ",":
                if depth == 0 { return words }
            default:
                if depth == 0 && token.kind == .word { words.append(token.text) }
            }
            cursor -= 1
        }
        return words
    }

    /// Whether the `(` at `index` opens a function's parameter list: `fn name(` or `fn name<T>(`.
    static func isParameterList(openingAt index: Int, in tokens: [Token]) -> Bool {
        var cursor = index - 1
        if cursor >= 0, [">", ">>"].contains(tokens[cursor].text) {
            guard let open = matchingAngle(closingAt: cursor, in: tokens) else { return false }
            cursor = open - 1
        }
        guard cursor >= 1, tokens[cursor].kind == .word else { return false }
        return tokens[cursor - 1].text == "fn"
    }

    /// Whether the cursor is between the pipes of a closure's parameters: `|a, |`, `|a: |`.
    private static func isInClosureParameters(_ input: Input) -> Bool {
        let tokens = input.tokens
        let start = enclosingOpenBracket(in: tokens, before: tokens.count - 1).map { $0 + 1 } ?? 0
        guard start < tokens.count else { return false }
        let pipes = tokens[start...].filter { $0.text == "|" }
        guard let first = tokens[start...].firstIndex(where: { $0.text == "|" }) else { return false }
        let opener = first > 0 ? tokens[first - 1].text : nil
        let opensClosure = opener == nil || ["(", ",", "=", "=>", "{", ";", "[", "move", "return"].contains(opener)
        return opensClosure && pipes.count % 2 == 1
    }

    /// Whether a `+` joins trait bounds: after `dyn`, `impl`, or `where`, inside generics, or after a bound's
    /// `:`.
    private static func isInTypeBounds(_ input: Input) -> Bool {
        let tokens = input.tokens
        let open = enclosingOpenBracket(in: tokens, before: tokens.count - 1)
        if let open, ["<", "::<"].contains(tokens[open].text) {
            return true
        }
        let start = open.map { $0 + 1 } ?? 0
        let segment = tokens[start..<(tokens.count - 1)]
        if segment.contains(where: { ["dyn", "impl", "where"].contains($0.text) }) {
            return true
        }
        guard let colon = segment.lastIndex(where: { $0.text == ":" }) else { return false }
        return intentAfterColon(input.ending(before: colon + 1)) == .typeName
    }

    /// The index of the innermost `(`, `[`, `{`, or generic `<` that is still open before `index`.
    ///
    /// A `<` counts as an opening angle bracket only right after a word (`Vec<`, `fn f<`) or as `::<`, and
    /// a `>` closes one only when an angle bracket is open, so comparisons (`a < b`) are not brackets.
    static func enclosingOpenBracket(in tokens: [Token], before index: Int) -> Int? {
        var depth = 0
        var angles = 0
        var cursor = index - 1
        while cursor >= 0 {
            let token = tokens[cursor]
            switch token.text {
            case ")", "]", "}":
                depth += 1
            case "(", "[", "{":
                if depth == 0 { return cursor }
                depth -= 1
            case ">":
                angles += 1
            case ">>":
                angles += 2
            case "<", "::<":
                if angles > 0 {
                    angles -= 1
                } else if depth == 0 && isGenericOpen(at: cursor, in: tokens) {
                    return cursor
                }
            default:
                break
            }
            cursor -= 1
        }
        return nil
    }

    /// The index of the `<` that the `>` or `>>` at `index` closes, or `nil` when none does.
    static func matchingAngle(closingAt index: Int, in tokens: [Token]) -> Int? {
        var angles = 0
        var cursor = index
        while cursor >= 0 {
            switch tokens[cursor].text {
            case ">": angles += 1
            case ">>": angles += 2
            case "<", "::<":
                angles -= 1
                if angles <= 0 { return angles == 0 ? cursor : nil }
            case ";", "{", "}":
                return nil
            default:
                break
            }
            cursor -= 1
        }
        return nil
    }

    private static func isGenericOpen(at index: Int, in tokens: [Token]) -> Bool {
        guard tokens[index].text == "<" else { return true }
        return index > 0 && tokens[index - 1].kind == .word && !tokens[index].hasLeadingSpace
    }
}
