//
//  ExpectedTypeResolver.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// What the resolver may ask about the document beyond its text. Production code backs these with
/// tree-sitter and the language server (see ``ExpectedTypeService``); tests pass closures.
struct ExpectedTypeEnvironment {
    /// Syntax node types around an offset, innermost first.
    var nodeTypesAt: (Int) -> [String] = { _ in [] }
    /// The range of the `field` child of the innermost node of type `ancestorType` around an offset.
    var fieldRange: (_ location: Int, _ ancestorType: String, _ field: String) -> NSRange? = { _, _, _ in nil }
    /// The type of the symbol that starts at an offset, from the language server's hover.
    var typeOfSymbol: (_ offset: Int) async -> TypeText? = { _ in nil }
    /// The type of the parameter the cursor is at when it sits in a call's argument list, from the
    /// language server's signature help.
    var activeParameterType: (_ offset: Int) async -> TypeText? = { _ in nil }
}

/// Works out the type the slot at the cursor expects, so the ranker can favor candidates of that type.
///
/// The slot is found from the text before the typed prefix: the operand being completed (`p.`,
/// `std::`) is skipped, and what stands before it decides the slot.
///
/// | Before the operand | Expected type |
/// | --- | --- |
/// | `T x =` | `T`, read from the declaration |
/// | `x =` | the type of `x`, from hover |
/// | `return` | the enclosing function's return type |
/// | `f(`, `f(a,` | the active parameter's type, from signature help |
/// | `if (`, `while (`, `!`, `&&`, `\|\|` | `bool` |
/// | `case` | the type of the enclosing `switch`'s condition, from hover |
/// | `T{`, `T(` (when no signature is known) | `T`, when tree-sitter says `T` is a type name |
///
/// Only the C family is resolved. Nothing here penalizes a candidate: no slot, no type.
struct ExpectedTypeResolver {
    /// The intents in which a value of some type is being written.
    static let intents: Set<CompletionIntent> = [.expression, .memberAccess, .scopeAccess, .caseLabel, .unknown]

    /// How much text before the cursor is looked at.
    private static let windowLength = 2_000

    let environment: ExpectedTypeEnvironment

    /// The type expected at the cursor, or `nil` when the slot is unknown.
    /// - Parameters:
    ///   - text: The document.
    ///   - prefixStart: The offset where the typed prefix starts.
    ///   - cursor: The cursor's offset.
    ///   - intent: What the user is writing at the cursor.
    ///   - languageId: The document's language identifier.
    func resolve(
        text: String,
        prefixStart: Int,
        cursor: Int,
        intent: CompletionIntent,
        languageId: String
    ) async -> TypeText? {
        guard CFamilyKeywords.languageIds.contains(languageId), Self.intents.contains(intent) else {
            return nil
        }
        let string = text as NSString
        guard prefixStart > 0, prefixStart <= string.length else { return nil }
        let windowStart = max(0, prefixStart - Self.windowLength)
        let before = string.substring(with: NSRange(location: windowStart, length: prefixStart - windowStart))
        let scanner = SlotScanner(units: Array(before.utf16), base: windowStart)
        guard let slot = scanner.slot() else { return nil }
        return await type(of: slot, text: string, prefixStart: prefixStart, cursor: cursor)
    }

    /// The type a `slot` expects.
    private func type(of slot: Slot, text: NSString, prefixStart: Int, cursor: Int) async -> TypeText? {
        switch slot {
        case .boolean:
            return TypeText.parse("bool")
        case .initialization(let type):
            return type
        case .assignment(let symbolOffset):
            return await environment.typeOfSymbol(symbolOffset)
        case .returnValue:
            return returnType(at: prefixStart, in: text)
        case .argument(let callee):
            return await environment.activeParameterType(cursor) ?? constructedType(callee)
        case .braceInitializer(let callee):
            return constructedType(callee)
        case .caseLabel(let conditionSymbolOffset):
            guard let conditionSymbolOffset else { return nil }
            return await environment.typeOfSymbol(conditionSymbolOffset)
        }
    }

    // MARK: - Slots that need the syntax tree

    /// The return type of the function around `location`, with the pointer stars of its declarator.
    private func returnType(at location: Int, in string: NSString) -> TypeText? {
        let types = environment.nodeTypesAt(location)
        if let lambda = types.firstIndex(of: "lambda_expression"),
           let function = types.firstIndex(of: "function_definition"),
           lambda < function {
            return nil
        }
        guard let typeRange = environment.fieldRange(location, "function_definition", "type"),
              NSMaxRange(typeRange) <= string.length else {
            return nil
        }
        var typeText = string.substring(with: typeRange)
        if let declaratorRange = environment.fieldRange(location, "function_definition", "declarator"),
           NSMaxRange(declaratorRange) <= string.length {
            let declarator = string.substring(with: declaratorRange)
            typeText += String(declarator.prefix { $0 == "*" || $0 == "&" || $0 == " " }.filter { $0 == "*" })
        }
        guard let type = TypeText.parse(typeText), !(type.name == "void" && type.pointerDepth == 0) else {
            return nil
        }
        return type
    }

    /// `T` for `T(` or `T{` when tree-sitter says the callee names a type.
    private func constructedType(_ callee: Callee) -> TypeText? {
        guard environment.nodeTypesAt(callee.nameStart).first == "type_identifier" else { return nil }
        return TypeText.parse(callee.text)
    }
}
