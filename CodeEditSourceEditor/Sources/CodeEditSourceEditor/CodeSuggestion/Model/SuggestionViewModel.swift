//
//  SuggestionViewModel.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 7/22/25.
//

import AppKit

@MainActor
final class SuggestionViewModel: ObservableObject {
    /// The items to be displayed in the window
    @Published var items: [CodeSuggestionEntry] = []
    var itemsRequestTask: Task<Void, Never>?
    private var requestID: UUID?
    weak var activeTextView: TextViewController?

    weak var delegate: CodeSuggestionDelegate?

    private var syntaxHighlightedCache: [Int: NSAttributedString] = [:]

    func showCompletions(
        textView: TextViewController,
        delegate: CodeSuggestionDelegate,
        cursorPosition: CursorPosition,
        showWindowOnParent: @escaping @MainActor (NSWindow, NSRect) -> Void
    ) {
        self.activeTextView = nil
        self.delegate = nil
        itemsRequestTask?.cancel()

        guard let targetParentWindow = textView.view.window else { return }

        self.activeTextView = textView
        self.delegate = delegate
        let requestID = UUID()
        self.requestID = requestID
        itemsRequestTask = Task {
            defer {
                if self.requestID == requestID { itemsRequestTask = nil }
            }

            do {
                let result = await delegate.completionSuggestionsRequested(
                    textView: textView,
                    cursorPosition: cursorPosition
                )
                guard let completionItems = result, !completionItems.items.isEmpty else {
                    return
                }

                try Task.checkCancellation()
                try await MainActor.run {
                    try Task.checkCancellation()
                    guard let cursorRect = screenRect(for: completionItems.windowPosition, in: textView) else {
                        return
                    }

                    self.items = completionItems.items
                    self.syntaxHighlightedCache = [:]
                    showWindowOnParent(targetParentWindow, cursorRect)
                }
            } catch {
                return
            }
        }
    }

    /// The screen rect of the character at `position`, used to anchor the completion window.
    private func screenRect(for position: CursorPosition, in textView: TextViewController) -> NSRect? {
        guard let resolved = textView.resolveCursorPosition(position),
              let localRect = textView.textView.layoutManager.rectForOffset(resolved.range.location) else {
            return nil
        }
        return textView.view.window?.convertToScreen(textView.textView.convert(localRect, to: nil))
    }

    func cursorsUpdated(
        textView: TextViewController,
        delegate: CodeSuggestionDelegate,
        position: CursorPosition,
        close: () -> Void
    ) {
        guard itemsRequestTask == nil else {
            close()
            return
        }

        if activeTextView !== textView {
            close()
            return
        }

        guard let newItems = delegate.completionOnCursorMove(
            textView: textView,
            cursorPosition: position
        ),
              !newItems.isEmpty else {
            close()
            return
        }

        items = newItems
    }

    func didSelect(item: CodeSuggestionEntry) {
        delegate?.completionWindowDidSelect(item: item)
    }

    /// Asks the delegate for the documentation that was left off the original completion list.
    func resolve(item: CodeSuggestionEntry) async -> CodeSuggestionEntry? {
        await delegate?.completionWindowResolve(item: item)
    }

    /// Replaces one row after resolve without treating the list as a new completion session.
    func replaceItem(at index: Int, with item: CodeSuggestionEntry) {
        guard items.indices.contains(index) else { return }
        syntaxHighlightedCache[index] = nil
        items[index] = item
    }

    func applySelectedItem(item: CodeSuggestionEntry, window: NSWindow?) {
        guard let activeTextView else {
            return
        }
        activeTextView.isApplyingCompletion = true
        defer { activeTextView.isApplyingCompletion = false }
        self.delegate?.completionWindowApplyCompletion(
            item: item,
            textView: activeTextView,
            cursorPosition: activeTextView.cursorPositions.first
        )
        willClose()
        window?.close()
    }

    func willClose() {
        requestID = nil
        itemsRequestTask?.cancel()
        itemsRequestTask = nil
        delegate?.completionWindowDidClose()
        delegate = nil
        items.removeAll()
        activeTextView = nil
    }

    func syntaxHighlights(forIndex index: Int) -> NSAttributedString? {
        if let cached = syntaxHighlightedCache[index] {
            return cached
        }

        if let sourcePreview = items[index].sourcePreview,
           let theme = activeTextView?.theme,
           let font = activeTextView?.font,
           let language = activeTextView?.language {
            let string = TreeSitterClient.quickHighlight(
                string: sourcePreview,
                theme: theme,
                font: font,
                language: language
            )
            syntaxHighlightedCache[index] = string
            return string
        }

        return nil
    }
}
