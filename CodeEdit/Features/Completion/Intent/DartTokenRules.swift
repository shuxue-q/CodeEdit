//
//  DartTokenRules.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/13/26.
//

/// The Dart rules of ``CompletionIntentRecognizer``: what the cursor's line and the syntax tree say
/// about where the user is in a `.dart` file.
///
/// The line decides first, the way the C-family rules do, because an unfinished line often parses as
/// `ERROR`:
///
/// - Member access after `.`, `?.`, `..`, `?..` (`context.`): ``CompletionIntent/memberAccess``.
/// - A type after `new`, `is`, `is!`, `as`, `extends`, `implements`, `with`, `on`, and inside `<`
///   (`List<`): ``CompletionIntent/typeName``. A declaration's parameter list is a type position too.
/// - A new declaration's name after `var`, `final`, `const`, `late`, or a type (`Widget `,
///   `List<int> `, `String? `): ``CompletionIntent/declarationName``.
/// - A call's arguments after `(` and `,` (`Text(`, `Padding(padding: x, `):
///   ``CompletionIntent/argument``.
/// - A value after a named argument's `:`, `=`, `return`, `=>`, `??`, or an operator (`child: `):
///   ``CompletionIntent/expression``.
/// - A statement start in a function or closure body: ``CompletionIntent/statement``; file, class,
///   mixin, extension, or enum scope: ``CompletionIntent/topLevel``.
/// - The name after `$` or inside `${` in a string (`'$na`, `'${us`):
///   ``CompletionIntent/variableReference``.
/// - Strings, `//` and `///` comments, and numbers: ``CompletionIntent/string``,
///   ``CompletionIntent/comment``, ``CompletionIntent/numberLiteral``.
///
/// `const ` starts a declaration only where a statement or member can start; in a value position
/// (`child: const `) it introduces a constant constructor call, a type position. The URI of an
/// `import`, `export`, or `part` directive is ``CompletionIntent/includePath``, where the analysis
/// server offers libraries.
///
/// When the line is inconclusive (a blank continuation line of a multi-line argument list, a new
/// statement), the innermost construct of the syntax tree decides (see ``DartKeywords/scopeIntents``).
/// The tree also covers what one line cannot see: a string or comment that started on an earlier line.
enum DartTokenRules {
    typealias Token = CompletionLineScanner.Token

    /// The tokens to classify, plus what the syntax tree says about the surrounding code.
    struct Input {
        /// The complete tokens before the prefix.
        let tokens: [Token]
        /// Whether whitespace separates the last token from the prefix.
        let hasTrailingSpace: Bool
        /// The intent of the innermost construct around the cursor, from the syntax tree.
        let scope: CompletionIntent?
    }

    /// Operator tokens that can only be followed by a value.
    private static let expressionOperators: Set<String> = [
        "=", "==", "!=", "<=", ">=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>=", ">>>=",
        "~/=", "??=", "??", "=>", "...", "...?", "+", "-", "*", "/", "%", "~/", "^", "|", "||", "&", "&&",
        "~", "<<", ">>>", "["
    ]

    /// Recognizes the intent for a Dart document.
    /// - Parameters:
    ///   - types: The node types around the cursor, innermost first. Empty without a syntax tree.
    ///   - prefix: The word being typed, up to the cursor.
    ///   - line: The cursor's line up to the cursor, including `prefix`.
    static func intent(types: [String], prefix: String, line: String) -> CompletionIntent {
        let scan = DartLineScanner.scan(line)
        switch scan.state {
        case .lineComment, .blockComment:
            return .comment
        case .interpolatedName:
            return .variableReference
        case .string:
            return isURIString(scan) ? .includePath : .string
        case .code:
            break
        }
        if types.contains(where: DartKeywords.commentNodes.contains) {
            return .comment
        }
        // A string that started on an earlier line (`'''`). The innermost node is the literal itself only
        // with the cursor in its text, not on a quote next to it.
        if !scan.isInInterpolation && types.first == "string_literal" {
            return .string
        }
        if prefix.first?.isNumber == true {
            return .numberLiteral
        }

        let code = scan.code.hasSuffix(prefix) ? String(scan.code.dropLast(prefix.count)) : scan.code
        let tokens = CompletionLineScanner.scan(code, dialect: .dart)
        let scope = scan.isInInterpolation ? nil : DartKeywords.scopeIntent(types)
        let input = Input(tokens: tokens.tokens, hasTrailingSpace: tokens.hasTrailingSpace, scope: scope)
        if let intent = intent(for: input) {
            return intent
        }
        // `'${us`: a name inside the braces of an interpolation.
        if scan.isInInterpolation {
            return .variableReference
        }
        return scope ?? .unknown
    }

    /// The intent the Dart token rules recognize, or `nil` when they are inconclusive.
    static func intent(for input: Input) -> CompletionIntent? {
        guard let last = input.tokens.last else { return nil }
        switch last.kind {
        case .word:
            return input.hasTrailingSpace ? intent(afterWord: last.text, input: input) : nil
        case .punctuation:
            return intent(afterPunctuation: last, input: input)
        case .number, .literal:
            return nil
        }
    }

    /// Whether the open string is the URI of an `import`, `export`, or `part` directive.
    private static func isURIString(_ scan: DartLineScanner.Result) -> Bool {
        guard !scan.isInInterpolation else { return false }
        let tokens = CompletionLineScanner.scan(scan.code, dialect: .dart).tokens
        guard let first = tokens.first?.text else { return false }
        return DartKeywords.uriDirectives.contains(first) && tokens.count <= 2
    }

    // MARK: - After a word

    private static func intent(afterWord word: String, input: Input) -> CompletionIntent? {
        if let intent = DartKeywords.intentAfterKeyword[word] {
            return intent
        }
        switch word {
        case "const":
            return startsDeclaration(before: input.tokens.count - 1, input: input) ? .declarationName : .typeName
        case "get", "set":
            // `int get name`, `set name(…)`.
            return .declarationName
        default:
            if DartKeywords.nonTypeKeywords.contains(word) {
                return nil
            }
            // `Widget name`, `final String name`, `void name`.
            return startsDeclaration(input.tokens, input: input) ? .declarationName : nil
        }
    }

    // MARK: - After punctuation

    private static func intent(afterPunctuation last: Token, input: Input) -> CompletionIntent? {
        let tokens = input.tokens
        switch last.text {
        case ".", "?.", "..", "?..":
            return .memberAccess
        case "<":
            let before = tokens.dropLast().last
            return before?.kind == .word && !last.hasLeadingSpace ? .typeName : .expression
        case ">", ">>":
            return intentAfterClosingAngle(input)
        case "(":
            return intentInsideParens(openingAt: tokens.count - 1, input: input, afterComma: false)
        case ",":
            return intentAfterComma(input)
        case ":":
            let first = tokens.first?.text
            return first == "case" || first == "default" ? .statement : .expression
        case "{":
            return intentAfterOpeningBrace(input)
        case "?", "!":
            return intentAfterSuffixOperator(last, input: input)
        case "@":
            return .expression
        default:
            return expressionOperators.contains(last.text) ? .expression : nil
        }
    }

    /// A `>` that closes type arguments ends a type (`List<int> |` names a variable); otherwise it is a
    /// comparison.
    private static func intentAfterClosingAngle(_ input: Input) -> CompletionIntent? {
        let tokens = input.tokens
        guard tokens.contains(where: { $0.text == "<" }), angleBalance(tokens[...]) == 0 else {
            return .expression
        }
        return input.hasTrailingSpace && startsDeclaration(tokens, input: input) ? .declarationName : nil
    }

    /// `String? |` names a variable, `a ? |` is a conditional; `x is! |` expects a type, `foo! |` is a
    /// null check, and `!|` negates a value.
    private static func intentAfterSuffixOperator(_ last: Token, input: Input) -> CompletionIntent? {
        let before = input.tokens.dropLast().last
        if last.text == "!" && before?.text == "is" && !last.hasLeadingSpace {
            return .typeName
        }
        let isPostfix = !last.hasLeadingSpace && (before?.kind == .word || [">", ")", "]"].contains(before?.text))
        guard isPostfix else { return .expression }
        if last.text == "?" {
            return input.hasTrailingSpace && startsDeclaration(input.tokens, input: input) ? .declarationName : nil
        }
        return nil
    }

    /// The intent inside the parentheses that open at `index`: a keyword's condition, a declaration's
    /// parameter list, a call's arguments, or a parenthesized expression, record, or closure parameters.
    private static func intentInsideParens(
        openingAt index: Int,
        input: Input,
        afterComma: Bool
    ) -> CompletionIntent {
        let before = input.tokens[..<index].last
        if let word = before, word.kind == .word {
            if let intent = DartKeywords.intentInsideParens[word.text] {
                // `catch (e, |` names the stack trace; the other keywords' commas separate values.
                return afterComma && word.text != "catch" ? .expression : intent
            }
            if DartKeywords.nonTypeKeywords.contains(word.text) && word.text != "super" && word.text != "this" {
                return .expression
            }
            return isParameterList(openingAt: index, input: input) ? .typeName : .argument
        }
        // `foo<int>(`, `f()(`, `list[0](`: calls without a plain name before the parenthesis.
        return [">", ">>", ")", "]"].contains(before?.text) ? .argument : .expression
    }

    private static func intentAfterComma(_ input: Input) -> CompletionIntent? {
        let tokens = input.tokens
        guard let open = enclosingOpenBracket(in: tokens, before: tokens.count - 1) else {
            // `implements A, |`, `with A, |`, `on A, |`. A comma ending a line of a multi-line argument or
            // parameter list is left to the syntax tree.
            let segment = currentSegment(Array(tokens.dropLast()), stoppingAtCommas: false)
            let hasTypeList = segment.tokens.contains { ["implements", "with", "on"].contains($0.text) }
            return hasTypeList ? .typeName : nil
        }
        switch tokens[open].text {
        case "<":
            return .typeName
        case "(":
            return intentInsideParens(openingAt: open, input: input, afterComma: true)
        case "{":
            return isNamedParameterBrace(at: open, input: input) ? .typeName : .expression
        default:
            return .expression
        }
    }

    /// `{` after a value position opens a map or set literal; after the `(` or `,` of a parameter
    /// list it opens the named parameters. Otherwise it opens a block or body, where the syntax tree
    /// decides.
    static func intentAfterOpeningBrace(_ input: Input) -> CompletionIntent? {
        let tokens = input.tokens
        guard let before = tokens.dropLast().last else { return nil }
        if before.text == "(" || before.text == "," {
            return isNamedParameterBrace(at: tokens.count - 1, input: input) ? .typeName : .expression
        }
        if before.kind == .word {
            return DartKeywords.expressionLeads.contains(before.text) || before.text == "const" ? .expression : nil
        }
        return expressionOperators.contains(before.text) || before.text == ":" ? .expression : nil
    }

    /// Whether the `{` at `index` opens the named parameters of a parameter list: `void f({`,
    /// `Foo(this.a, {`.
    static func isNamedParameterBrace(at index: Int, input: Input) -> Bool {
        guard index > 0, ["(", ","].contains(input.tokens[index - 1].text),
              let paren = enclosingOpenBracket(in: input.tokens, before: index),
              input.tokens[paren].text == "(" else {
            return false
        }
        return isParameterList(openingAt: paren, input: input)
    }
}
