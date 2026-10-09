//
//  CMakeLineScanner.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

/// A small CMake lexer for the text on the cursor's line before the typed prefix.
///
/// CMake shares nothing with the C scanner (``CompletionLineScanner``): `#` starts a comment (`#[[ … ]]`
/// for a bracket comment), `//` is an ordinary character, only `"` quotes, a backslash escapes in
/// quoted and unquoted arguments, and `${…}`, `$ENV{…}`, and `$CACHE{…}` references expand inside
/// quoted text as well. The scanner answers the questions the intent rules ask: is the cursor in a
/// comment, in a string, in a variable reference, or in a command's parentheses?
///
/// It sees one line. A bracket argument or a quoted string that opened on an earlier line is the
/// syntax tree's to know; see ``CMakeTokenRules``.
enum CMakeLineScanner {
    /// What kind of reference is open at the end of the text.
    enum Reference: Equatable {
        /// `${`.
        case variable
        /// `$ENV{`.
        case environment
        /// `$CACHE{`.
        case cache

        /// The text that opens the reference.
        var opening: String {
            switch self {
            case .variable: return "${"
            case .environment: return "$ENV{"
            case .cache: return "$CACHE{"
            }
        }
    }

    /// Where the end of the scanned text sits, apart from references.
    enum State: Equatable {
        /// In unquoted code.
        case code
        /// Inside an unterminated `"…"` argument.
        case quoted
        /// Inside an unterminated bracket argument `[[ …`.
        case bracketArgument
        /// After `#`.
        case lineComment
        /// Inside an unterminated bracket comment `#[[ …`.
        case bracketComment

        /// Whether the state is inside a comment.
        var isComment: Bool { self == .lineComment || self == .bracketComment }
        /// Whether the state is inside quoted text.
        var isString: Bool { self == .quoted || self == .bracketArgument }
    }

    /// The outcome of scanning a line.
    struct Result: Equatable {
        /// Where the end of the text sits. `.quoted` also when a reference is open inside a quote.
        let state: State
        /// The innermost `${`, `$ENV{`, or `$CACHE{` that is still open, if any.
        let reference: Reference?
        /// How many `(` are still open. Command arguments sit between a `(` and its `)`.
        let parenthesisDepth: Int
        /// The last non-blank character of the code, outside comments and quotes. `)` means a
        /// command just ended.
        let lastCodeCharacter: Character?
        /// Whether a quoted argument closed exactly at the end of the text, so the cursor sits right
        /// after the closing quote rather than inside the literal.
        let endsWithClosedQuote: Bool
        /// Whether the text holds nothing but whitespace.
        let isBlank: Bool
    }

    /// Scans `text`, which should be the cursor's line up to (not including) the typed prefix.
    static func scan(_ text: String) -> Result {
        var lexer = Lexer(text)
        let ending = lexer.run()
        var reference: Reference?
        if case .reference(let open)? = lexer.frames.last {
            reference = open
        }
        return Result(
            state: lexer.frames.contains(.quoted) ? .quoted : ending,
            reference: reference,
            parenthesisDepth: lexer.depth,
            lastCodeCharacter: lexer.lastCode,
            endsWithClosedQuote: lexer.closedQuoteAtEnd,
            isBlank: lexer.chars.allSatisfy(\.isWhitespace)
        )
    }

    /// One thing that can be open at the end of the text, innermost last.
    private enum Frame: Equatable {
        case quoted
        case reference(Reference)
    }

    /// The scanner's position and what is open at it.
    private struct Lexer {
        let chars: [Character]
        var frames: [Frame] = []
        var depth = 0
        var lastCode: Character?
        var closedQuoteAtEnd = false
        var index = 0

        init(_ text: String) {
            chars = Array(text)
        }

        /// Reads all the text and returns the state it ends in.
        mutating func run() -> State {
            while index < chars.count {
                let char = chars[index]
                closedQuoteAtEnd = false
                if char == "\\" {
                    // An escape takes the next character with it: `\${`, `\"`, `\(`.
                    if frames.isEmpty { lastCode = char }
                    index += 2
                } else if char == "$", let reference = CMakeLineScanner.reference(at: index, in: chars) {
                    frames.append(.reference(reference))
                    if frames.count == 1 { lastCode = char }
                    index += reference.opening.count
                } else if case .reference? = frames.last {
                    readReferenceCharacter(char)
                } else if frames.contains(.quoted) {
                    readQuotedCharacter(char)
                } else if let ending = readCodeCharacter(char) {
                    return ending
                }
            }
            return .code
        }

        /// A character inside `${…}`: `}` closes it, and whitespace outside quotes cancels it, since an
        /// unquoted argument ends there.
        private mutating func readReferenceCharacter(_ char: Character) {
            if char == "}" {
                frames.removeLast()
            } else if char.isWhitespace && !frames.contains(.quoted) {
                frames.removeAll()
            }
            index += 1
        }

        /// A character inside a quoted argument, outside any reference.
        private mutating func readQuotedCharacter(_ char: Character) {
            if char == "\"" {
                frames.removeLast()
                closedQuoteAtEnd = index == chars.count - 1
                lastCode = char
            }
            index += 1
        }

        /// A character in unquoted code. Returns the state the text ends in when it ends here, in an
        /// unterminated comment or bracket argument.
        private mutating func readCodeCharacter(_ char: Character) -> State? {
            if char.isWhitespace {
                index += 1
            } else if char == "#" {
                if let end = CMakeLineScanner.bracketEnd(in: chars, openingAt: index + 1) {
                    index = end
                } else {
                    let isBracket = CMakeLineScanner.bracketOpening(in: chars, at: index + 1) != nil
                    return isBracket ? .bracketComment : .lineComment
                }
            } else if char == "[", CMakeLineScanner.bracketOpening(in: chars, at: index) != nil {
                guard let end = CMakeLineScanner.bracketEnd(in: chars, openingAt: index) else {
                    return .bracketArgument
                }
                lastCode = "]"
                index = end
            } else {
                if char == "\"" {
                    frames.append(.quoted)
                } else if char == "(" {
                    depth += 1
                } else if char == ")" {
                    depth = max(0, depth - 1)
                }
                lastCode = char
                index += 1
            }
            return nil
        }
    }

    /// The reference that opens at `index` (which holds a `$`), if any.
    private static func reference(at index: Int, in chars: [Character]) -> Reference? {
        let candidates: [Reference] = [.cache, .environment, .variable]
        return candidates.first { matches($0.opening, in: chars, at: index) }
    }

    /// The number of `=` in the bracket opener (`[`, any number of `=`, `[`) at `index`, or `nil`.
    private static func bracketOpening(in chars: [Character], at index: Int) -> Int? {
        guard index < chars.count, chars[index] == "[" else { return nil }
        var cursor = index + 1
        while cursor < chars.count, chars[cursor] == "=" {
            cursor += 1
        }
        guard cursor < chars.count, chars[cursor] == "[" else { return nil }
        return cursor - index - 1
    }

    /// The index just past the `]=…=]` that closes the bracket opened at `index`, or `nil` when it
    /// is not closed in `chars`.
    private static func bracketEnd(in chars: [Character], openingAt index: Int) -> Int? {
        guard let level = bracketOpening(in: chars, at: index) else { return nil }
        let closer = Array("]" + String(repeating: "=", count: level) + "]")
        var cursor = index + level + 2
        while cursor + closer.count <= chars.count {
            if Array(chars[cursor..<(cursor + closer.count)]) == closer {
                return cursor + closer.count
            }
            cursor += 1
        }
        return nil
    }

    private static func matches(_ string: String, in chars: [Character], at index: Int) -> Bool {
        let candidate = Array(string)
        guard index + candidate.count <= chars.count else { return false }
        return Array(chars[index..<(index + candidate.count)]) == candidate
    }
}
