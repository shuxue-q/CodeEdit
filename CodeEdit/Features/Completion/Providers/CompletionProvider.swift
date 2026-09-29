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
    /// only when no zero-deadline provider returned anything.
    var deadline: Duration { get }

    /// Characters that should open the completion window as they're typed.
    func triggerCharacters() -> Set<String>

    /// Produces candidates for the current context. May be cancelled if the cursor moves away.
    func candidates(for context: CompletionContext, textView: TextViewController) async -> [CompletionCandidate]

    /// Applies `candidate` to the document.
    func apply(_ candidate: CompletionCandidate, textView: TextViewController, cursorPosition: CursorPosition?)

    /// Fills in documentation/detail left off the original candidate. Returns `nil` to keep it as-is.
    func resolve(_ candidate: CompletionCandidate) async -> CompletionCandidate?
}

extension CompletionProvider {
    func triggerCharacters() -> Set<String> { [] }
    func resolve(_ candidate: CompletionCandidate) async -> CompletionCandidate? { nil }
}

/// A `CompletionProvider` whose primary source is `.ai`. Used by the aggregator to identify the
/// provider that may answer after its deadline and needs late-merge handling.
@MainActor
protocol AICompletionProvider: CompletionProvider { }
