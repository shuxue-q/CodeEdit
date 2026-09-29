//
//  TextViewController+Format.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit contributors on 9/28/26.
//

import AppKit
import CodeEditTextView

extension TextViewController {

    /// Formats the document, or the selected lines when a selection exists.
    ///
    /// The context-menu delegate performs the format. When no delegate handles it, a bezel is shown.
    @objc
    public func formatCode(_ sender: Any?) {
        guard isEditable else { return }
        let source = textView.textStorage.string
        let cursor = formatCursorUTF8(in: source)
        let lineRanges = formatLineRanges()
        let handled = contextMenuDelegate?.formatCode(
            text: source,
            fileURL: fileURL,
            cursorUTF8: cursor,
            lineRanges: lineRanges
        ) { [weak self] result in
            guard let self else { return }
            guard case let .formatted(text, cursor) = result else { return }
            guard self.textView.textStorage.string == source else { return }
            self.applyFormattedText(text, cursor: cursor)
        } ?? false
        if !handled {
            BezelNotification.show(symbolName: "text.alignleft", over: textView)
        }
    }

    /// Replaces the buffer with formatted text and moves the caret.
    ///
    /// Edit filters are suspended so they do not rewrite the formatted text.
    private func applyFormattedText(_ formatted: String, cursor: Int?) {
        guard formatted != textView.textStorage.string else { return }
        let fallback = textView.selectionManager.textSelections.first?.range.location ?? 0
        isApplyingFormat = true
        defer { isApplyingFormat = false }
        textView.replaceCharacters(
            in: NSRange(location: 0, length: textView.textStorage.length),
            with: formatted,
            skipUpdateSelection: true
        )
        let utf16Length = (formatted as NSString).length
        let location = min(max(0, cursor ?? fallback), utf16Length)
        textView.selectionManager.setSelectedRange(NSRange(location: location, length: 0))
        textView.scrollSelectionToVisible()
    }

    /// UTF-8 byte offset of the first caret, which clang-format's `--cursor` expects.
    private func formatCursorUTF8(in source: String) -> Int? {
        guard let range = textView.selectionManager.textSelections.first?.range else { return nil }
        let nsSource = source as NSString
        let location = min(max(0, range.location), nsSource.length)
        return nsSource.substring(to: location).utf8.count
    }

    /// 1-based inclusive line ranges covering each non-empty selection. Empty formats the whole file.
    private func formatLineRanges() -> [ClosedRange<Int>] {
        textView.selectionManager.textSelections.compactMap { selection in
            guard selection.range.length > 0 else { return nil }
            let startOffset = selection.range.location
            let endOffset = max(startOffset, selection.range.upperBound - 1)
            guard let startLine = textView.layoutManager.textLineForOffset(startOffset),
                  let endLine = textView.layoutManager.textLineForOffset(endOffset) else {
                return nil
            }
            return (startLine.index + 1)...(endLine.index + 1)
        }
    }
}
