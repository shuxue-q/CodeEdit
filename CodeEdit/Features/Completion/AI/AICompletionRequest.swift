//
//  AICompletionRequest.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// A backend-independent description of one AI completion request: the code around the cursor and what
/// is known about the slot being filled. Each ``AICompletionBackend`` turns it into its vendor's wire format.
struct AICompletionRequest: Sendable, Equatable {
    /// The text before the cursor, already truncated to the prompt budget.
    let before: String
    /// The text after the cursor, already truncated to the prompt budget.
    let after: String
    /// The word being typed.
    let prefix: String
    /// The language identifier, for example `"cpp"`.
    let languageId: String
    /// A short description of what the user is typing, from the completion intent.
    let intentDescription: String
    /// The type the slot at the cursor expects, when it is known.
    let expectedType: String?
    /// The normalized type of the object whose members are being completed, when it is known.
    let receiverType: String?
    /// The header of the function around the cursor, when there is one.
    let functionSignature: String?
    /// The most suggestions the model is asked for.
    let maxSuggestions: Int

    /// Creates a request.
    init(
        before: String,
        after: String,
        prefix: String,
        languageId: String,
        intentDescription: String,
        expectedType: String? = nil,
        receiverType: String? = nil,
        functionSignature: String? = nil,
        maxSuggestions: Int = AICompletionPrompt.maxSuggestions
    ) {
        self.before = before
        self.after = after
        self.prefix = prefix
        self.languageId = languageId
        self.intentDescription = intentDescription
        self.expectedType = expectedType
        self.receiverType = receiverType
        self.functionSignature = functionSignature
        self.maxSuggestions = maxSuggestions
    }
}

/// One suggestion returned by a backend.
struct AICompletionSuggestion: Sendable, Equatable {
    /// The short label shown in the completion window.
    let label: String
    /// The exact text inserted when the suggestion is accepted.
    let insertText: String
}
