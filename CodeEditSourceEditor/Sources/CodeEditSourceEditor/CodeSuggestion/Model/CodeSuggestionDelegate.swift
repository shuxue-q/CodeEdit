//
//  CodeSuggestionDelegate.swift
//  CodeEditSourceEditor
//
//  Created by Abe Malla on 12/26/24.
//

/// The answer to a completion request: where to anchor the window, the rows, and which row to preselect.
public struct CodeSuggestionResult {
    /// The cursor position the window is anchored at.
    public var windowPosition: CursorPosition
    /// The rows to show.
    public var items: [CodeSuggestionEntry]
    /// The row that is a strong best match, selected and drawn in bold. `nil` when no row stands out;
    /// the first row is then highlighted as usual.
    public var preselectedIndex: Int?

    /// Creates a result.
    public init(windowPosition: CursorPosition, items: [CodeSuggestionEntry], preselectedIndex: Int? = nil) {
        self.windowPosition = windowPosition
        self.items = items
        self.preselectedIndex = preselectedIndex
    }
}

/// The refreshed rows after the cursor moved while the window was open.
public struct CodeSuggestionUpdate {
    /// The rows to show.
    public var items: [CodeSuggestionEntry]
    /// The row that is a strong best match, or `nil`. See ``CodeSuggestionResult/preselectedIndex``.
    public var preselectedIndex: Int?

    /// Creates an update.
    public init(items: [CodeSuggestionEntry], preselectedIndex: Int? = nil) {
        self.items = items
        self.preselectedIndex = preselectedIndex
    }
}

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

    /// Requests completions and returns which row to preselect along with the rows.
    ///
    /// The window calls this instead of the tuple-returning variants. The default calls
    /// ``completionSuggestionsRequested(textView:cursorPosition:trigger:)`` and preselects nothing, so
    /// existing delegates keep working unchanged.
    func completionSuggestionsResult(
        textView: TextViewController,
        cursorPosition: CursorPosition,
        trigger: CodeSuggestionTrigger
    ) async -> CodeSuggestionResult?

    /// Refreshes the rows after the cursor moved while the window is open, with the row to preselect.
    ///
    /// The window calls this instead of ``completionOnCursorMove(textView:cursorPosition:)``. The
    /// default calls that method and preselects nothing.
    func completionSuggestionsUpdated(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) -> CodeSuggestionUpdate?

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
    func completionSuggestionsResult(
        textView: TextViewController,
        cursorPosition: CursorPosition,
        trigger: CodeSuggestionTrigger
    ) async -> CodeSuggestionResult? {
        guard let result = await completionSuggestionsRequested(
            textView: textView,
            cursorPosition: cursorPosition,
            trigger: trigger
        ) else {
            return nil
        }
        return CodeSuggestionResult(windowPosition: result.windowPosition, items: result.items)
    }
    func completionSuggestionsUpdated(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) -> CodeSuggestionUpdate? {
        completionOnCursorMove(textView: textView, cursorPosition: cursorPosition)
            .map { CodeSuggestionUpdate(items: $0) }
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
