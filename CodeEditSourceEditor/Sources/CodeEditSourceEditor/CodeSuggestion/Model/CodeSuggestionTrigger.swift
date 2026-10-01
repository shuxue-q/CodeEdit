//
//  CodeSuggestionTrigger.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit Contributors on 9/30/26.
//

/// How a completion request was started.
public enum CodeSuggestionTrigger: Sendable, Equatable {
    /// Typing a letter, number, or trigger character opened the window automatically.
    case typing
    /// The user asked for completions, for example with the show-completions key binding.
    case explicit
}
