//
//  CompletionPayload.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import LanguageServerProtocol

/// What is needed to apply a completion candidate back into the text view.
///
/// Applying an item goes back to the owning provider, which keeps its own text-edit, `#include`,
/// and snippet tab-stop behavior.
enum CompletionPayload {
    /// A language-server completion item, applied through its `textEdit` or `insertText`.
    case lsp(CompletionItem)
    /// A snippet body, in LSP snippet syntax (`${1:cond}`, `$0`).
    case snippet(body: String)
    /// Plain text inserted verbatim, replacing the typed prefix.
    case plain(insertText: String)
}
