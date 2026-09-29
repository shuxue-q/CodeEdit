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
    func completionWindowDidClose() { }
    func completionWindowDidSelect(item: CodeSuggestionEntry) { }
    func completionWindowResolve(item: CodeSuggestionEntry) async -> CodeSuggestionEntry? { nil }
}
