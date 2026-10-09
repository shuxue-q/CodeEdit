//
//  ExpectedTypeSlotScanner.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// The name written before a call's `(` or an initializer's `{`, and where it starts.
struct Callee {
    /// The whole chain, for example `std::string`.
    let text: String
    /// Where the last name of the chain starts: the identifier tree-sitter classifies.
    let nameStart: Int
}

/// What the cursor is in the position of.
enum Slot {
    /// A condition, a negation or a logical operand.
    case boolean
    /// The initializer of a declaration whose type is known.
    case initialization(TypeText?)
    /// The right-hand side of an assignment to the symbol that starts at this offset.
    case assignment(Int)
    /// A `return` operand.
    case returnValue
    /// An argument of a call to `callee`.
    case argument(Callee)
    /// An element of `T{…}`.
    case braceInitializer(Callee)
    /// A `case` label of a `switch` whose condition names a symbol at this offset (if it does).
    case caseLabel(Int?)
}

/// Looks backwards through the text before the typed prefix. Works on UTF-16 units, like `NSString`.
struct SlotScanner {
    let units: [UInt16]
    /// The document offset of `units[0]`.
    let base: Int

    private func char(_ index: Int) -> Character? {
        guard units.indices.contains(index), let scalar = Unicode.Scalar(units[index]) else { return nil }
        return Character(scalar)
    }

    private func isIdentifier(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber || character == "_"
    }

    private func text(_ range: Range<Int>) -> String {
        String(utf16CodeUnits: Array(units[range]), count: range.count)
    }

    /// The index just before the operand that ends at `end`: a member or scope chain such as
    /// `a.b(c)[d]->e::f`, with nothing between its parts.
    private func skipOperand(from end: Int) -> Int {
        var index = end
        while index > 0 {
            let current = char(index - 1)
            let previous = char(index - 2)
            if isIdentifier(current) || current == "." {
                index -= 1
            } else if current == ">" && previous == "-" || current == ":" && previous == ":" {
                index -= 2
            } else if current == ")" || current == "]" {
                guard let open = matchingOpen(forCloseAt: index - 1) else { return index }
                index = open
            } else {
                break
            }
        }
        return index
    }

    /// The index of the bracket that opens the one closing at `close`.
    private func matchingOpen(forCloseAt close: Int) -> Int? {
        var depth = 0
        var index = close
        while index >= 0 {
            switch char(index) {
            case ")", "]", "}": depth += 1
            case "(", "[", "{":
                depth -= 1
                if depth == 0 { return index }
            default: break
            }
            index -= 1
        }
        return nil
    }

    private func skipSpaces(before index: Int) -> Int {
        var current = index
        while current > 0, char(current - 1)?.isWhitespace == true { current -= 1 }
        return current
    }

    /// The word that ends at `end` and the index it starts at.
    private func word(endingAt end: Int) -> (text: String, start: Int)? {
        var start = end
        while start > 0, isIdentifier(char(start - 1)) { start -= 1 }
        guard start < end else { return nil }
        return (text(start..<end), start)
    }

    /// The callee written before the bracket at `open`: `f`, `ns::T`, `a.b`.
    private func callee(beforeBracketAt open: Int) -> Callee? {
        let end = skipSpaces(before: open)
        let start = skipOperand(from: end)
        guard start < end else { return nil }
        let name = text(start..<end)
        guard name.first.map({ $0.isLetter || $0 == "_" || $0 == ":" }) == true else { return nil }
        return Callee(text: name, nameStart: base + (word(endingAt: end)?.start ?? start))
    }

    func slot() -> Slot? {
        let operandStart = skipOperand(from: units.count)
        let end = skipSpaces(before: operandStart)
        guard end > 0, let last = char(end - 1) else { return nil }
        if let slot = punctuationSlot(last, endingAt: end) { return slot }
        guard isIdentifier(last), let word = word(endingAt: end) else { return nil }
        switch word.text {
        case "return": return .returnValue
        case "case": return .caseLabel(switchConditionSymbol(before: word.start))
        default: return nil
        }
    }

    /// The slot after the operator or bracket `last`, which ends at `end`.
    private func punctuationSlot(_ last: Character, endingAt end: Int) -> Slot? {
        let before = char(end - 2)
        switch last {
        case "=":
            guard before.map({ !"=!<>+-*/%&|^".contains($0) }) ?? true else { return nil }
            return equalsSlot(at: end - 1)
        case "(":
            return openParenSlot(at: end - 1)
        case ",":
            return enclosingOpenParen(before: end - 1).flatMap(openParenSlot)
        case "!":
            return .boolean
        case "&" where before == "&", "|" where before == "|":
            return .boolean
        case "{":
            return callee(beforeBracketAt: end - 1).map(Slot.braceInitializer)
        default:
            return nil
        }
    }

    // MARK: Equals

    /// The slot after the `=` at `equals`: a declaration's initializer or an assignment.
    private func equalsSlot(at equals: Int) -> Slot? {
        var statementStart = equals
        var depth = 0
        while statementStart > 0 {
            let character = char(statementStart - 1)
            if ")" == character || "]" == character { depth += 1 }
            if "(" == character || "[" == character {
                if depth == 0 { break }
                depth -= 1
            }
            if depth == 0, ";" == character || "{" == character || "}" == character { break }
            statementStart -= 1
        }
        let statement = text(statementStart..<equals)
        if let declared = Self.declaredType(in: statement) {
            return .initialization(declared.type)
        }
        guard let symbol = Self.assignedSymbol(in: statement) else { return nil }
        return .assignment(base + statementStart + symbol)
    }

    private static let declarationPattern: NSRegularExpression? = {
        let qualifier = #"(?:(?:const|constexpr|static|volatile|inline|extern|thread_local|mutable|register)\s+)*"#
        let modifiers = #"(?:(?:unsigned|signed|long|short)\s+)*"#
        let name = #"(?:struct\s+|class\s+|enum\s+)?[A-Za-z_]\w*(?:::[A-Za-z_]\w*)*"#
        let pattern = "^\\s*" + qualifier + "(" + modifiers + name + #"(?:<.*>)?(?:::[A-Za-z_]\w*)*)"#
            + #"(?:\s+|(?=[*&]))((?:[*&]+\s*(?:const\s*)?)*)\s*[A-Za-z_]\w*\s*(?:\[[^\]]*\])?\s*$"#
        return try? NSRegularExpression(pattern: pattern)
    }()

    /// The type a statement such as `const std::string &s` declares, or `nil` if it is not a declaration.
    static func declaredType(in statement: String) -> (type: TypeText?, text: String)? {
        let range = NSRange(statement.startIndex..., in: statement)
        guard let match = declarationPattern?.firstMatch(in: statement, range: range),
              let typeRange = Range(match.range(at: 1), in: statement),
              let declaratorRange = Range(match.range(at: 2), in: statement) else {
            return nil
        }
        let typeText = String(statement[typeRange])
        let stars = statement[declaratorRange].filter { $0 == "*" }
        guard !["return", "else", "new", "delete", "throw", "case", "goto", "typedef"].contains(typeText) else {
            return nil
        }
        return (TypeText.parse(typeText + stars), typeText)
    }

    private static let assignmentTarget = try? NSRegularExpression(
        pattern: #"^\s*([A-Za-z_]\w*(?:\s*(?:\.|->|::)\s*[A-Za-z_]\w*)*)\s*$"#
    )

    /// The offset in `statement` of the last name in an assigned member chain such as `a.b->c`.
    static func assignedSymbol(in statement: String) -> Int? {
        let range = NSRange(statement.startIndex..., in: statement)
        guard let match = assignmentTarget?.firstMatch(in: statement, range: range) else { return nil }
        let chain = match.range(at: 1)
        let nsStatement = statement as NSString
        var start = NSMaxRange(chain)
        while start > chain.location {
            let character = nsStatement.substring(with: NSRange(location: start - 1, length: 1))
            guard character.first.map({ $0.isLetter || $0.isNumber || $0 == "_" }) == true else { break }
            start -= 1
        }
        return start
    }

    // MARK: Parentheses

    /// The slot inside the parenthesis at `open`.
    private func openParenSlot(at open: Int) -> Slot? {
        let end = skipSpaces(before: open)
        if let word = word(endingAt: end) {
            switch word.text {
            case "if", "while": return .boolean
            case "for", "switch", "sizeof", "alignof", "decltype", "catch", "return", "case": return nil
            default: break
            }
        }
        return callee(beforeBracketAt: open).map(Slot.argument)
    }

    /// The `(` that encloses index `index`, skipping balanced groups. `nil` at a statement boundary.
    private func enclosingOpenParen(before index: Int) -> Int? {
        var depth = 0
        var current = index
        while current > 0 {
            current -= 1
            switch char(current) {
            case ")", "]": depth += 1
            case "[": depth = max(0, depth - 1)
            case "(":
                if depth == 0 { return current }
                depth -= 1
            case ";", "{", "}": return nil
            default: break
            }
        }
        return nil
    }

    // MARK: Switch

    /// The offset of the last name in the condition of the `switch` whose body contains `index`.
    private func switchConditionSymbol(before index: Int) -> Int? {
        var depth = 0
        var current = index
        var openBrace: Int?
        while current > 0 {
            current -= 1
            let character = char(current)
            if character == "}" {
                depth += 1
            } else if character == "{" {
                if depth == 0 {
                    openBrace = current
                    break
                }
                depth -= 1
            }
        }
        guard let openBrace else { return nil }
        let close = skipSpaces(before: openBrace)
        guard close > 0, char(close - 1) == ")", let open = matchingOpen(forCloseAt: close - 1) else { return nil }
        let keywordEnd = skipSpaces(before: open)
        guard word(endingAt: keywordEnd)?.text == "switch" else { return nil }
        let condition = text((open + 1)..<(close - 1))
        guard let symbol = Self.assignedSymbol(in: condition) else { return nil }
        return base + open + 1 + symbol
    }
}
