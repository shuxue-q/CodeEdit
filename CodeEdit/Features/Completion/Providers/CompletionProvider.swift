//
//  CompletionProvider.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import CodeEditSourceEditor

/// A source of completion candidates fanned out to by ``CompletionAggregator``.
///
/// The aggregator queries all providers concurrently. Providers with a zero `deadline` are awaited
/// in full; a provider with a deadline (typically ``AICompletionProvider``) never delays the window
/// once the others have answered, and a late result is merged in on the next cursor move.
@MainActor
protocol CompletionProvider: AnyObject {
    /// The primary source this provider's candidates are badged with.
    var source: CompletionSource { get }
    /// `.zero` to always wait for this provider; otherwise the longest the window waits for it, and
    /// only when no zero-deadline provider returned anything. A later answer is merged in on the next
    /// cursor move.
    var deadline: Duration { get }
    /// How long the window waits for a provider with a `deadline` even when other providers already
    /// returned candidates, so a fast server's items are in the first list instead of the second.
    /// Never longer than `deadline`. The default is `.zero`: do not wait.
    var graceDeadline: Duration { get }

    /// Characters that should open the completion window as they're typed.
    func triggerCharacters() -> Set<String>

    /// Produces candidates for the current context. May be cancelled if the cursor moves away.
    func candidates(for context: CompletionContext, textView: TextViewController) async -> [CompletionCandidate]

    /// Applies `candidate` to the document.
    func apply(_ candidate: CompletionCandidate, textView: TextViewController, cursorPosition: CursorPosition?)

    /// Applies `candidate`, which the user accepted by typing `commitCharacter` (`nil` for Return, Tab,
    /// or a click). The editor inserts the character itself afterwards. The default ignores it.
    func apply(
        _ candidate: CompletionCandidate,
        textView: TextViewController,
        cursorPosition: CursorPosition?,
        commitCharacter: Character?
    )

    /// Fills in documentation/detail left off the original candidate. Returns `nil` to keep it as-is.
    func resolve(_ candidate: CompletionCandidate) async -> CompletionCandidate?
}

extension CompletionProvider {
    var graceDeadline: Duration { .zero }
    func triggerCharacters() -> Set<String> { [] }
    func apply(
        _ candidate: CompletionCandidate,
        textView: TextViewController,
        cursorPosition: CursorPosition?,
        commitCharacter: Character?
    ) {
        apply(candidate, textView: textView, cursorPosition: cursorPosition)
    }
    func resolve(_ candidate: CompletionCandidate) async -> CompletionCandidate? { nil }
}

/// A `CompletionProvider` whose primary source is `.ai`. Used by the aggregator to identify the
/// provider that may answer after its deadline and needs late-merge handling.
@MainActor
protocol AICompletionProvider: CompletionProvider { }
