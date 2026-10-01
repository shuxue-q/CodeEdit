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
}
