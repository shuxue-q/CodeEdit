//
//  CodeSuggestionDelegate.swift
//  CodeEditSourceEditor
//
//  Created by Abe Malla on 12/26/24.
//

@MainActor
public protocol CodeSuggestionDelegate: AnyObject {
    func completionTriggerCharacters() -> Set<String>

    func completionSuggestionsRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])?

    /// Requests completions, saying whether the user typed (`.typing`) or asked for them (`.explicit`).
    ///
    /// Implement this to treat the two differently, for example to stay quiet while the user types in
    /// a comment. The default implementation calls
    /// ``completionSuggestionsRequested(textView:cursorPosition:)``.
    func completionSuggestionsRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition,
        trigger: CodeSuggestionTrigger
    ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])?

    // This can't be async, we need it to be snappy. At most, it should just be filtering completion items
    func completionOnCursorMove(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) -> [CodeSuggestionEntry]?

    // Optional
    func completionWindowDidClose()

    func completionWindowApplyCompletion(
        item: CodeSuggestionEntry,
        textView: TextViewController,
        cursorPosition: CursorPosition?
    )
    // Optional
    func completionWindowDidSelect(item: CodeSuggestionEntry)

    /// Fills in documentation and detail for the item the user has highlighted.
    ///
    /// Servers often leave these empty until `completionItem/resolve`. Return nil to keep `item`.
    func completionWindowResolve(item: CodeSuggestionEntry) async -> CodeSuggestionEntry?

    /// The characters that accept `item` when typed while it is the highlighted row.
    ///
    /// Typing one of them applies the item and then inserts the character, so `foo(` completes
    /// `foo` and leaves the caret after the parenthesis. The window only commits when something has
    /// been typed since the completion site (the character before the caret is part of a word), so
    /// `obj.` followed by `(` never accepts the first member. The default is `[]`: no commit characters.
    func completionCommitCharacters(for item: CodeSuggestionEntry) -> Set<Character>

    /// Applies `item`, which the user accepted by typing `commitCharacter`, or by Return, Tab or a
    /// double-click when `commitCharacter` is `nil`.
    ///
    /// The window inserts `commitCharacter` itself right after this call returns, so an
    /// implementation should not add it. The default calls
    /// ``completionWindowApplyCompletion(item:textView:cursorPosition:)``.
    func completionWindowApplyCompletion(
        item: CodeSuggestionEntry,
        textView: TextViewController,
        cursorPosition: CursorPosition?,
        commitCharacter: Character?
    )
}

public extension CodeSuggestionDelegate {
    func completionTriggerCharacters() -> Set<String> { [] }
    func completionSuggestionsRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition,
        trigger: CodeSuggestionTrigger
    ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])? {
        await completionSuggestionsRequested(textView: textView, cursorPosition: cursorPosition)
    }
    func completionWindowDidClose() { }
    func completionWindowDidSelect(item: CodeSuggestionEntry) { }
    func completionWindowResolve(item: CodeSuggestionEntry) async -> CodeSuggestionEntry? { nil }
    func completionCommitCharacters(for item: CodeSuggestionEntry) -> Set<Character> { [] }
    func completionWindowApplyCompletion(
        item: CodeSuggestionEntry,
        textView: TextViewController,
        cursorPosition: CursorPosition?,
        commitCharacter: Character?
    ) {
        completionWindowApplyCompletion(item: item, textView: textView, cursorPosition: cursorPosition)
    }
}
