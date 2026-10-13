//
//  DartTokenRules+Declarations.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/13/26.
//

/// Where a Dart declaration can start, which tokens form a type, and how the brackets and statement
/// boundaries before the cursor nest.
extension DartTokenRules {
    // MARK: - Declarations

    /// Whether the token at `index` stands where a declaration can start: only modifiers precede it
    /// since a statement boundary (`const |`, `static const |`).
    static func startsDeclaration(before index: Int, input: Input) -> Bool {
        let segment = currentSegment(Array(input.tokens[..<index]))
        guard segment.tokens.allSatisfy({ DartKeywords.typeModifiers.contains($0.text) }) else { return false }
        return isDeclarationBoundary(segment.boundary, in: input.tokens, input: input)
    }

    /// Whether `tokens` end with a type that starts a declaration: the tokens since the last boundary
    /// form a type, and that boundary allows a declaration.
    static func startsDeclaration(_ tokens: [Token], input: Input) -> Bool {
        let segment = currentSegment(tokens)
        return isTypePhrase(segment.tokens[...]) && isDeclarationBoundary(segment.boundary, in: tokens, input: input)
    }

    /// Whether a declaration can start after the boundary token at `boundary` (`nil`: the line start).
    ///
    /// At the start of a line, the syntax tree decides: a new line in an argument list or a list
    /// literal (`const Text(…),` on its own line) is a value, not a declaration.
    static func isDeclarationBoundary(_ boundary: Int?, in tokens: [Token], input: Input) -> Bool {
        guard let boundary else {
            return input.scope != .argument && input.scope != .expression
        }
        switch tokens[boundary].text {
        case ";", "}":
            return true
        case "{":
            return intentAfterOpeningBrace(Input(
                tokens: Array(tokens[...boundary]),
                hasTrailingSpace: false,
                scope: input.scope
            )) != .expression
        case "(":
            return tokens[..<boundary].last?.text == "for" || isParameterList(openingAt: boundary, input: input)
        case ",":
            guard let open = enclosingOpenBracket(in: tokens, before: boundary) else {
                // A parameter on its own line of a multi-line parameter list.
                return input.scope == .typeName
            }
            if tokens[open].text == "{" {
                return isNamedParameterBrace(at: open, input: input)
            }
            return tokens[open].text == "(" && isParameterList(openingAt: open, input: input)
        default:
            return false
        }
    }

    /// Whether the `(` at `index` opens a declaration's parameter list: `void f(`, `Widget build(`,
    /// `Foo.named(` in a class body. A call such as `foo(` or `Padding(` has no type before its name;
    /// a bare name is a declaration only at class or file scope, where a call cannot start.
    static func isParameterList(openingAt index: Int, input: Input) -> Bool {
        let tokens = input.tokens
        guard index > 0, tokens[index - 1].kind == .word else { return false }
        var nameStart = index - 1
        // `Foo.named(`: a named constructor.
        if nameStart >= 2, tokens[nameStart - 1].text == ".", tokens[nameStart - 2].kind == .word {
            nameStart -= 2
        }
        let segment = currentSegment(Array(tokens[..<nameStart]))
        let boundaryText = segment.boundary.map { tokens[$0].text }
        if let boundaryText, ![";", "{", "}"].contains(boundaryText) {
            return false
        }
        if boundaryText == nil && (input.scope == .argument || input.scope == .expression) {
            return false
        }
        let modifiers: Set<String> = ["const", "factory", "external", "static"]
        if segment.tokens.allSatisfy({ modifiers.contains($0.text) }) {
            return input.scope == .topLevel
        }
        return isTypePhrase(segment.tokens[...])
    }

    /// Whether `tokens` read as a type, optionally after modifiers: words that are not statement or
    /// expression keywords, joined by `.` (a library prefix), with type arguments and a trailing `?`.
    static func isTypePhrase(_ tokens: ArraySlice<Token>) -> Bool {
        guard tokens.first?.kind == .word else { return false }
        var angle = 0
        var sawType = false
        for token in tokens {
            switch token.kind {
            case .word:
                if DartKeywords.nonTypeKeywords.contains(token.text) { return false }
                let isModifier = DartKeywords.typeModifiers.contains(token.text)
                    || DartKeywords.declarationLeads.contains(token.text)
                sawType = sawType || !isModifier
            case .number, .literal:
                return false
            case .punctuation:
                guard isTypePunctuation(token, angle: &angle) else { return false }
            }
        }
        return angle == 0 && sawType
    }

    static func isTypePunctuation(_ token: Token, angle: inout Int) -> Bool {
        let text = token.text
        switch text {
        case ".":
            return true
        case "?":
            // `String?` is nullable; a spaced `a ? b` is a conditional.
            return !token.hasLeadingSpace
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

    // MARK: - Brackets and segments

    /// The tokens since the last declaration or statement boundary at bracket depth zero, and the index
    /// of that boundary token (`nil` when the segment starts the line).
    static func currentSegment(
        _ tokens: [Token],
        stoppingAtCommas: Bool = true
    ) -> (tokens: [Token], boundary: Int?) {
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
                if depth == 0, DartKeywords.segmentBoundaries.contains(text), stoppingAtCommas || text != "," {
                    return (Array(tokens[index...]), index - 1)
                }
            }
            index -= 1
        }
        return (tokens, nil)
    }

    static func angleBalance(_ tokens: ArraySlice<Token>) -> Int {
        tokens.reduce(0) { balance, token in
            switch token.text {
            case "<": return balance + 1
            case ">", ">>": return balance - token.text.count
            default: return balance
            }
        }
    }

    /// The index of the unclosed `(`, `<`, `[`, or `{` enclosing the token at `end`, if any.
    static func enclosingOpenBracket(in tokens: [Token], before end: Int) -> Int? {
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
