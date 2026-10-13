//
//  RustTokenRules.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/13/26.
//

/// The Rust rules of ``CompletionIntentRecognizer``: what the cursor's line and the syntax tree say about
/// where the user is in a `.rs` file.
///
/// The line decides first, the way the C-family and Dart rules do, because an unfinished line often
/// parses as `ERROR`:
///
/// - Member access after `.` (`self.`, `x?.`): ``CompletionIntent/memberAccess``.
/// - A path after `::` (`std::`, `Self::`) and anywhere in a `use` declaration:
///   ``CompletionIntent/scopeAccess``.
/// - A new name after `let`, `let mut`, `fn`, `struct`, `enum`, `trait`, `mod`, `const`, `static`, `type`,
///   a loop's `for`, and in a function's or closure's parameter list: ``CompletionIntent/declarationName``.
/// - A type after a binding's or parameter's `:`, `->`, `impl`, `dyn`, `as`, `where`, `impl … for`, a
///   bound's `:` or `+`, inside generics (`Vec<`, `::<`), and after `&` or `&mut` there:
///   ``CompletionIntent/typeName``. A lone `'` starts a lifetime, a type position too.
/// - A value after `=`, `return`, `=>`, `if`, `while`, `match`, `in`, `if let`, a call's or macro's `(` and
///   `,`, a struct literal's field `:`, and operators: ``CompletionIntent/expression``.
/// - Inside an attribute (`#[`, `#![`, `#[derive(`): ``CompletionIntent/preprocessor``, Rust's
///   compile-time directives.
/// - Strings, comments, and numbers: ``CompletionIntent/string``, ``CompletionIntent/comment``,
///   ``CompletionIntent/numberLiteral``.
///
/// When the line is inconclusive (a new line), the innermost construct of the syntax tree decides (see
/// ``RustKeywords/scopeIntents``): a block is a statement position, the file and `impl`, `trait`, and `mod`
/// bodies are item positions, a struct's body starts a field name. The tree also covers what one line
/// cannot see: a comment or string that started on an earlier line.
enum RustTokenRules {
    typealias Token = CompletionLineScanner.Token

    /// The tokens to classify, plus what the syntax tree says about the surrounding code.
    struct Input {
        /// The complete tokens before the prefix.
        let tokens: [Token]
        /// Whether whitespace separates the last token from the prefix.
        let hasTrailingSpace: Bool
        /// The intent of the innermost construct around the cursor, from the syntax tree.
        let scope: CompletionIntent?

        /// The same input ending before the token at `index`, as if the cursor stood right after the token
        /// before it.
        func ending(before index: Int) -> Input {
            Input(
                tokens: Array(tokens[..<index]),
                hasTrailingSpace: index < tokens.count && tokens[index].hasLeadingSpace,
                scope: scope
            )
        }
    }

    /// Recognizes the intent for a Rust document.
    /// - Parameters:
    ///   - types: The node types around the cursor, innermost first. Empty without a syntax tree.
    ///   - prefix: The word being typed, up to the cursor.
    ///   - line: The cursor's line up to the cursor, including `prefix`.
    static func intent(types: [String], prefix: String, line: String) -> CompletionIntent {
        let scan = RustLineScanner.scan(line)
        switch scan.state {
        case .lineComment, .blockComment:
            return .comment
        case .string, .character:
            return .string
        case .code:
            break
        }
        if types.contains(where: RustKeywords.commentNodes.contains) {
            return .comment
        }
        // A string that started on an earlier line.
        if let innermost = types.first, RustKeywords.stringContentNodes.contains(innermost) {
            return .string
        }

        let code = scan.code.hasSuffix(prefix) ? String(scan.code.dropLast(prefix.count)) : scan.code
        let scanned = CompletionLineScanner.scan(code, dialect: .rust)
        // `pair.0`: a tuple field, not a number literal.
        if scanned.tokens.last?.text == ".", !scanned.hasTrailingSpace {
            return .memberAccess
        }
        if prefix.first?.isNumber == true {
            return .numberLiteral
        }
        let input = Input(
            tokens: scanned.tokens,
            hasTrailingSpace: scanned.hasTrailingSpace,
            scope: RustKeywords.scopeIntent(types)
        )
        return intent(for: input) ?? input.scope ?? .unknown
    }

    /// The intent the Rust token rules recognize, or `nil` when they are inconclusive.
    static func intent(for input: Input) -> CompletionIntent? {
        if isInAttribute(input.tokens) {
            return .preprocessor
        }
        if let intent = useDeclarationIntent(input) {
            return intent
        }
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

    // MARK: - Attributes and `use`

    /// Whether the tokens end inside an attribute: after `#` or `#!`, or inside the brackets of `#[…` or
    /// `#![…`.
    static func isInAttribute(_ tokens: [Token]) -> Bool {
        var depth = 0
        var index = 0
        while index < tokens.count {
            let text = tokens[index].text
            if depth > 0 {
                if text == "[" { depth += 1 }
                if text == "]" { depth -= 1 }
            } else if text == "#" {
                var next = index + 1
                if next < tokens.count && tokens[next].text == "!" { next += 1 }
                if next == tokens.count { return true }
                if tokens[next].text == "[" {
                    depth = 1
                    index = next
                }
            }
            index += 1
        }
        return depth > 0
    }

    /// Anywhere in a `use` declaration the user writes a path: ``CompletionIntent/scopeAccess``, except the
    /// new name after `as`.
    private static func useDeclarationIntent(_ input: Input) -> CompletionIntent? {
        let tokens = input.tokens
        guard let useIndex = tokens.lastIndex(where: { $0.kind == .word && $0.text == "use" }),
              !tokens[useIndex...].contains(where: { $0.text == ";" }),
              startsStatement(at: useIndex, in: tokens) else {
            return nil
        }
        if useIndex == tokens.count - 1 && !input.hasTrailingSpace {
            return nil
        }
        if tokens.last?.text == "as" && input.hasTrailingSpace {
            return .declarationName
        }
        return .scopeAccess
    }

    /// Whether the token at `index` starts a statement or item: nothing, `;`, a brace, or an attribute's `]`
    /// precedes it, after any visibility (`pub`, `pub(crate)`).
    private static func startsStatement(at index: Int, in tokens: [Token]) -> Bool {
        var cursor = index - 1
        if cursor >= 0 && tokens[cursor].text == ")" {
            guard let open = tokens[..<cursor].lastIndex(where: { $0.text == "(" }) else { return false }
            cursor = open - 1
        }
        if cursor >= 0 && tokens[cursor].text == "pub" {
            cursor -= 1
        }
        return cursor < 0 || [";", "{", "}", "]"].contains(tokens[cursor].text)
    }

    // MARK: - After a word

    private static func intent(afterWord word: String, input: Input) -> CompletionIntent? {
        let tokens = input.tokens
        let before = tokens.count >= 2 ? tokens[tokens.count - 2].text : nil
        if word.hasPrefix("'") {
            // `&'a |`: the type follows the lifetime.
            return before == "&" ? .typeName : nil
        }
        switch word {
        case "let":
            // `if let |`, `while let |`, `a && let |`: a pattern, usually a variant such as `Some(`.
            return ["if", "while", "&&"].contains(before) ? .expression : .declarationName
        case "mut":
            return intentAfterMut(input)
        case "const":
            // `*const |` is a raw pointer type; otherwise a constant's name follows.
            return before == "*" ? .typeName : .declarationName
        case "for":
            return statementHead(tokens).contains("impl") ? .typeName : .declarationName
        default:
            return RustKeywords.intentAfterKeyword[word]
        }
    }

    /// `&mut |` continues whatever `&` started (a type or a value), `*mut |` is a raw pointer type, and
    /// elsewhere (`let mut`, `fn f(mut`, `static mut`) a binding's name follows.
    private static func intentAfterMut(_ input: Input) -> CompletionIntent {
        let tokens = input.tokens
        guard tokens.count >= 2 else { return .declarationName }
        switch tokens[tokens.count - 2].text {
        case "&":
            return intentAfterReference(input.ending(before: tokens.count - 1))
        case "*":
            return .typeName
        default:
            return .declarationName
        }
    }

    /// The words of the statement or item that holds the end of `tokens`: everything after the last `;`,
    /// `{`, or `}`.
    static func statementHead(_ tokens: [Token]) -> [String] {
        let start = tokens.lastIndex { [";", "{", "}"].contains($0.text) }.map { $0 + 1 } ?? 0
        return tokens[start...].filter { $0.kind == .word }.map(\.text)
    }
}
