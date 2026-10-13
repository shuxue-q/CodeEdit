//
//  DartLineScanner.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/13/26.
//

/// Reads the cursor's line in a Dart file up to the cursor and says whether the cursor is in code, a
/// comment, a string, or an interpolation inside a string.
///
/// Dart strings nest code: `'Hello ${user.name}'` and `'Hello $name'` both interpolate, and the code
/// inside `${…}` can hold strings of its own. The C-family scanner reads a quote to the next quote,
/// so this scanner runs first and hands it plain code: the line, or the inside of the innermost open
/// `${`, with every complete string literal replaced by `''` and every closed comment by a space.
///
/// It also handles raw strings (`r'C:\path'`, no escapes and no interpolation), triple-quoted strings
/// that open and close on the line, and nested block comments. A string or comment that started on an
/// earlier line is invisible here; ``DartTokenRules`` asks the syntax tree about those.
enum DartLineScanner {
    /// Where the end of the scanned text sits.
    enum State: Equatable {
        /// In code: at file scope, in a body, or inside `${…}`.
        case code
        /// After `//` or `///`.
        case lineComment
        /// Inside an unterminated `/* …`.
        case blockComment
        /// Inside the text of an unterminated string.
        case string
        /// Right after `$` in a non-raw string, on the name being interpolated (`'Hi $na`).
        case interpolatedName
    }

    /// The outcome of scanning a line.
    struct Result: Equatable {
        /// Where the end of the text sits.
        let state: State
        /// For ``State/code``, the code to tokenize: the line, or the inside of the innermost open
        /// `${`. For a string state, the code before the open string, so `import '` can be told apart
        /// from other strings. Complete string literals read `''`; closed comments read as a space.
        let code: String
        /// Whether the code sits inside an open `${`.
        let isInInterpolation: Bool
    }

    /// An open string literal.
    private struct OpenString {
        let quote: Character
        let isTriple: Bool
        let isRaw: Bool
    }

    /// One level of nesting: code (the line itself, or an interpolation) or a string.
    private enum Context {
        case code(text: [Character], braceDepth: Int)
        case string(OpenString)
    }

    /// Scans `text`, the cursor's line up to the cursor.
    static func scan(_ text: String) -> Result {
        let chars = Array(text)
        var stack: [Context] = [.code(text: [], braceDepth: 0)]
        var index = 0

        while index < chars.count {
            switch stack[stack.count - 1] {
            case .code:
                if let early = scanCode(chars, at: &index, stack: &stack) {
                    return early
                }
            case .string(let open):
                if let early = scanString(open, chars, at: &index, stack: &stack) {
                    return early
                }
            }
        }
        if case .string = stack[stack.count - 1] {
            return result(.string, stack: stack)
        }
        return result(.code, stack: stack)
    }

    // MARK: - Code

    /// Consumes one step of code at `index`. Returns a result when the rest of the line is a comment.
    private static func scanCode(_ chars: [Character], at index: inout Int, stack: inout [Context]) -> Result? {
        let char = chars[index]
        let next = index + 1 < chars.count ? chars[index + 1] : nil

        if char == "/" && next == "/" {
            return result(.lineComment, stack: stack)
        }
        if char == "/" && next == "*" {
            guard let end = closingBlockComment(in: chars, from: index + 2) else {
                return result(.blockComment, stack: stack)
            }
            appendCode(" ", to: &stack)
            index = end
            return nil
        }
        if let open = openingQuote(in: chars, at: index) {
            stack.append(.string(open.string))
            index = open.end
            return nil
        }
        if case let .code(text, depth) = stack[stack.count - 1] {
            if char == "{" {
                stack[stack.count - 1] = .code(text: text + [char], braceDepth: depth + 1)
            } else if char == "}" && depth == 0 && stack.count > 1 {
                // The `}` that closes `${…}`: back to the string around it.
                stack.removeLast()
            } else {
                stack[stack.count - 1] = .code(text: text + [char], braceDepth: char == "}" ? depth - 1 : depth)
            }
        }
        index += 1
        return nil
    }

    /// The string that opens at `index` (`'`, `"`, a triple quote, or a raw `r'…`), and the index just
    /// past its opening quote. An `r` that ends an identifier (`bar'`) does not make a raw string.
    private static func openingQuote(
        in chars: [Character],
        at index: Int
    ) -> (string: OpenString, end: Int)? {
        var start = index
        var isRaw = false
        if chars[index] == "r", index + 1 < chars.count, chars[index + 1] == "'" || chars[index + 1] == "\"",
           index == 0 || !CompletionLineScanner.isWordCharacter(chars[index - 1]) {
            isRaw = true
            start = index + 1
        }
        let quote = chars[start]
        guard quote == "'" || quote == "\"" else { return nil }
        let isTriple = start + 2 < chars.count && chars[start + 1] == quote && chars[start + 2] == quote
        return (OpenString(quote: quote, isTriple: isTriple, isRaw: isRaw), start + (isTriple ? 3 : 1))
    }

    // MARK: - Strings

    /// Consumes one step of string text at `index`. Returns a result when the line ends on an
    /// interpolated name.
    private static func scanString(
        _ open: OpenString,
        _ chars: [Character],
        at index: inout Int,
        stack: inout [Context]
    ) -> Result? {
        let char = chars[index]
        if !open.isRaw && char == "\\" {
            index += 2
            return nil
        }
        if char == open.quote, closes(open, in: chars, at: index) {
            stack.removeLast()
            appendCode("''", to: &stack)
            index += open.isTriple ? 3 : 1
            return nil
        }
        guard !open.isRaw, char == "$" else {
            index += 1
            return nil
        }
        let next = index + 1 < chars.count ? chars[index + 1] : nil
        if next == "{" {
            stack.append(.code(text: [], braceDepth: 0))
            index += 2
            return nil
        }
        // `$name`: the name runs to the first character that cannot be in an identifier. `$` itself
        // cannot continue an interpolated name.
        var end = index + 1
        while end < chars.count, chars[end].isLetter || chars[end].isNumber || chars[end] == "_" {
            end += 1
        }
        if end == chars.count {
            return result(.interpolatedName, stack: stack)
        }
        index = max(end, index + 1)
        return nil
    }

    private static func closes(_ open: OpenString, in chars: [Character], at index: Int) -> Bool {
        guard open.isTriple else { return true }
        return index + 2 < chars.count && chars[index + 1] == open.quote && chars[index + 2] == open.quote
    }

    // MARK: - Helpers

    /// The index just past the `*/` that closes a block comment opened before `start`. Dart block
    /// comments nest.
    private static func closingBlockComment(in chars: [Character], from start: Int) -> Int? {
        var depth = 1
        var index = start
        while index + 1 < chars.count {
            if chars[index] == "*" && chars[index + 1] == "/" {
                depth -= 1
                index += 2
                if depth == 0 { return index }
            } else if chars[index] == "/" && chars[index + 1] == "*" {
                depth += 1
                index += 2
            } else {
                index += 1
            }
        }
        return nil
    }

    /// Appends `text` to the innermost code context.
    private static func appendCode(_ text: String, to stack: inout [Context]) {
        guard let index = stack.lastIndex(where: { if case .code = $0 { return true } else { return false } }),
              case let .code(code, depth) = stack[index] else {
            return
        }
        stack[index] = .code(text: code + Array(text), braceDepth: depth)
    }

    /// The result for `state`: the innermost code context's text, and whether it is an interpolation.
    private static func result(_ state: State, stack: [Context]) -> Result {
        let codeIndex = stack.lastIndex { if case .code = $0 { return true } else { return false } } ?? 0
        guard case .code(let text, _) = stack[codeIndex] else {
            return Result(state: state, code: "", isInInterpolation: false)
        }
        return Result(state: state, code: String(text), isInInterpolation: codeIndex > 0)
    }
}
