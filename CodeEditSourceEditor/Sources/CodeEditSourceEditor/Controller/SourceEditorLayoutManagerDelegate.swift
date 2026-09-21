//
//  SourceEditorLayoutManagerDelegate.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit on 2026-09-17.
//

import AppKit
import CodeEditTextView

/// A delegate proxy for `TextLayoutManager` that forwards layout calls to `TextView`
/// while constraining `textViewportSize` to `reformatAtColumn` when line wrapping is enabled.
final class SourceEditorLayoutManagerDelegate: TextLayoutManagerDelegate {
    weak var textView: TextView?
    weak var controller: TextViewController?

    init(textView: TextView, controller: TextViewController) {
        self.textView = textView
        self.controller = controller
    }

    func layoutManagerHeightDidUpdate(newHeight: CGFloat) {
        textView?.layoutManagerHeightDidUpdate(newHeight: newHeight)
    }

    func layoutManagerMaxWidthDidChange(newWidth: CGFloat) {
        textView?.layoutManagerMaxWidthDidChange(newWidth: newWidth)
    }

    func layoutManagerTypingAttributes() -> [NSAttributedString.Key: Any] {
        textView?.layoutManagerTypingAttributes() ?? [:]
    }

    func textViewportSize() -> CGSize {
        guard let textView else { return .zero }
        var size = textView.textViewportSize()
        if let controller,
           controller.wrapLines,
           controller.reformatAtColumn > 0,
           controller.font.charWidth > 0 {
            let charAdvance = controller.font.charWidth * CGFloat(controller.letterSpacing)
            let maxTextWidth = CGFloat(controller.reformatAtColumn) * charAdvance
            let maxWidthWithInsets = maxTextWidth + textView.layoutManager.edgeInsets.horizontal
            size.width = min(size.width, maxWidthWithInsets)
        }
        return size
    }

    func layoutManagerYAdjustment(_ yAdjustment: CGFloat) {
        textView?.layoutManagerYAdjustment(yAdjustment)
    }

    var visibleRect: NSRect {
        textView?.visibleRect ?? .zero
    }
}
