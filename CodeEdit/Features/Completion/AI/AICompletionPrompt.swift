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

    /// The system prompt every backend sends.
    static let systemPrompt = """
    You complete source code. Given the code immediately before and after a <cursor/> marker, \
    suggest up to 3 short completions that could be inserted at the cursor. Each suggestion is a \
    short label and the exact text to insert. Do not repeat code that is already present. If \
    nothing reasonable can be suggested, return an empty list.
    """

    /// Builds the request for `context`.
    static func request(for context: CompletionContext) -> AICompletionRequest {
        let (before, after) = split(context)
        return AICompletionRequest(
            before: before,
            after: after,
            prefix: context.prefix,
            languageId: context.languageId,
            intentDescription: context.intent.promptDescription
        )
    }

    /// The user message every backend sends for `request`.
    static func userMessage(for request: AICompletionRequest) -> String {
        """
        Language: \(request.languageId)
        The user is typing \(request.intentDescription).
        Code before the cursor:
        \(request.before)<cursor/>\(request.after)
        """
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
