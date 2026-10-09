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
    /// What the user is most likely writing at the cursor.
    var intent: CompletionIntent
    /// The language server / tree-sitter language identifier, for example `"cpp"`.
    var languageId: String
    /// A window of the document's text around the cursor.
    var documentText: String
    /// The cursor's offset into the document.
    var cursorOffset: Int
    /// `true` when the user explicitly asked for completions rather than triggering them by typing.
    var isExplicit: Bool = false
    /// The identifiers that occur in the document. A candidate named like one of them is a symbol the
    /// file already uses, which the ranker favors. Empty when they have not been collected.
    var documentIdentifiers: Set<String> = []
    /// The type the slot at the cursor expects (the declared type in `std::string s = `, the return type
    /// after `return`, the active parameter's type in a call), when it could be worked out in time.
    /// The ranker favors candidates of this type. `nil` means unknown, never a penalty.
    var expectedType: TypeText?
    /// The normalized type of the object whose members are being completed (`std::vector<int>` for
    /// `v.` when `v` is such a vector), when it could be worked out in time. Member statistics are kept
    /// per receiver type. `nil` means unknown.
    var receiverType: String?
    /// `true` when the user asked for chain completion (members reachable through a symbol that fit the
    /// expected type) instead of the regular list.
    var isChain = false
}
