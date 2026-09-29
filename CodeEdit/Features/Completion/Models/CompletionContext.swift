//
//  CompletionContext.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import Foundation

/// Everything a ``CompletionProvider`` needs to produce candidates for the current cursor position.
struct CompletionContext {
    /// The word being typed, up to the cursor.
    var prefix: String
    /// The range of `prefix` in the document.
    var prefixRange: NSRange
    /// The character that opened the completion window, if any.
    var triggerCharacter: String?
    /// The syntactic position of the cursor.
    var syntax: SyntacticContext
    /// The language server / tree-sitter language identifier, for example `"cpp"`.
    var languageId: String
    /// A window of the document's text around the cursor.
    var documentText: String
    /// The cursor's offset into the document.
    var cursorOffset: Int
    /// `true` when the user explicitly asked for completions rather than triggering them by typing.
    var isExplicit: Bool = false
}
