//
//  TextView+TextFormation.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 10/14/23.
//

import Foundation
import CodeEditTextView
import TextStory
import TextFormation

extension TextView: @retroactive TextStoring {}
extension TextView: @retroactive TextInterface {
    public var selectedRange: NSRange {
        get {
            return selectionManager
                .textSelections
                .sorted(by: { $0.range.lowerBound < $1.range.lowerBound })
                .first?
                .range ?? .zero
        }
        set {
            selectionManager.setSelectedRange(newValue)
        }
    }

    public var length: Int {
        textStorage.length
    }

    public func substring(from range: NSRange) -> String? {
        return textStorage.substring(from: range)
    }

    /// Applies the mutation to the text view.
    ///
    /// Notifies the text view delegate around the storage change. Newline, indent, and bracket
    /// filters apply their edits here instead of ``TextView/replaceCharacters(in:with:skipUpdateSelection:)``.
    /// Language servers only observe the delegate, so skipping the notification drops those edits
    /// and the server's copy of the file diverges from the editor.
    ///
    /// If the mutation is empty it will be ignored.
    ///
    /// - Parameter mutation: The mutation to apply.
    public func applyMutation(_ mutation: TextMutation) {
        guard !mutation.isEmpty else { return }
        // Delegate first, while the storage still has the pre-edit text, so ranges match that text.
        delegate?.textView(self, willReplaceContentsIn: mutation.range, with: mutation.string)
        _undoManager?.registerMutation(mutation)
        textStorage.replaceCharacters(in: mutation.range, with: mutation.string)
        selectionManager.didReplaceCharacters(
            in: mutation.range,
            replacementLength: (mutation.string as NSString).length
        )
        delegate?.textView(self, didReplaceContentsIn: mutation.range, with: mutation.string)
        layoutManager.invalidateLayoutForRange(mutation.range)
    }
}
