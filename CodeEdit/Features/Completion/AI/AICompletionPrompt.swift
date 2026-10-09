//
//  AICompletionPrompt.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// The prompt text shared by every AI backend, and the code that builds an ``AICompletionRequest`` from a
/// ``CompletionContext``.
enum AICompletionPrompt {
    /// How much of the document before the cursor is sent, in characters.
    static let maxPrefixContextLength = 4_000
    /// How much of the document after the cursor is sent, in characters.
    static let maxSuffixContextLength = 1_000
    /// The most suggestions requested per completion.
    static let maxSuggestions = 3
    /// The most the semantic lines (function header, expected type, receiver type) add to the prompt, in
    /// characters.
    static let maxExtraContextLength = 600
    /// The longest a type name in the semantic lines may be, in characters.
    private static let maxTypeLength = 120

    /// The system prompt every backend sends.
    static let systemPrompt = """
    You complete source code. Given the code immediately before and after a <cursor/> marker, \
    suggest up to 3 short completions that could be inserted at the cursor. Each suggestion is a \
    short label and the exact text to insert. Do not repeat code that is already present. If \
    nothing reasonable can be suggested, return an empty list.
    """

    /// Builds the request for `context`. `semantics` are the facts resolved alongside the providers; the
    /// expected and receiver types already on `context` take precedence.
    static func request(
        for context: CompletionContext,
        semantics: ResolvedSemantics = .none
    ) -> AICompletionRequest {
        let (before, after) = split(context)
        return AICompletionRequest(
            before: before,
            after: after,
            prefix: context.prefix,
            languageId: context.languageId,
            intentDescription: context.intent.promptDescription,
            expectedType: (context.expectedType ?? semantics.expectedType)?.description,
            receiverType: context.receiverType ?? semantics.receiverType,
            functionSignature: semantics.functionSignature
        )
    }

    /// The user message every backend sends for `request`. Without any semantic facts it is exactly the
    /// language, the intent and the code around the cursor.
    static func userMessage(for request: AICompletionRequest) -> String {
        let extra = extraContext(for: request).map { $0 + "\n" } ?? ""
        return """
        Language: \(request.languageId)
        The user is typing \(request.intentDescription).
        \(extra)Code before the cursor:
        \(request.before)<cursor/>\(request.after)
        """
    }

    /// The lines that tell the model what the cursor position expects, or `nil` when nothing is known. Capped
    /// at ``maxExtraContextLength`` characters.
    ///
    /// TODO: public declarations of the `#include`d project headers would help too, but resolving and
    /// reading them is too slow and too large for a request that has to stay under the popup deadline.
    static func extraContext(for request: AICompletionRequest) -> String? {
        var lines: [String] = []
        if let signature = request.functionSignature, !signature.isEmpty {
            let header = inline(signature, limit: FunctionSignatureText.maxLength)
            lines.append("The cursor is inside this function: `\(header)`.")
        }
        if let type = request.expectedType, !type.isEmpty {
            lines.append("The expression should produce a `\(inline(type, limit: maxTypeLength))`.")
        }
        if let type = request.receiverType, !type.isEmpty {
            lines.append("The object before the cursor has the type `\(inline(type, limit: maxTypeLength))`.")
        }
        guard !lines.isEmpty else { return nil }
        return String(lines.joined(separator: "\n").prefix(maxExtraContextLength))
    }

    /// `text` on one line, without backticks, cut to `limit` characters.
    private static func inline(_ text: String, limit: Int) -> String {
        let singleLine = text.replacingOccurrences(of: "`", with: "'")
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
        return String(singleLine.prefix(limit))
    }

    /// Splits `context.documentText` around `context.cursorOffset` (a UTF-16, `NSString`-style
    /// offset, matching every other cursor offset in this feature) and truncates both sides.
    static func split(_ context: CompletionContext) -> (before: String, after: String) {
        let text = context.documentText as NSString
        let offset = max(0, min(context.cursorOffset, text.length))
        let before = text.substring(to: offset)
        let after = text.substring(from: offset)
        return (String(before.suffix(maxPrefixContextLength)), String(after.prefix(maxSuffixContextLength)))
    }
}
