//
//  SourceEditorTextView.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 7/23/25.
//

import AppKit
import CodeEditTextView

final class SourceEditorTextView: TextView {
    weak var controller: TextViewController?
    var additionalCursorRects: [(NSRect, NSCursor)] = []

    override func resetCursorRects() {
        discardCursorRects()
        super.resetCursorRects()
        additionalCursorRects.forEach { (rect, cursor) in
            addCursorRect(rect, cursor: cursor)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        updateSelectionForContextMenu(at: event)
        if let contextMenu = controller?.buildContextMenu(for: event) {
            self.menu = contextMenu
            NSMenu.popUpContextMenu(contextMenu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    private func updateSelectionForContextMenu(at event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let offset = layoutManager.textOffsetAtPoint(point) {
            let hasSelection = selectionManager.textSelections.contains {
                $0.range.length > 0 && $0.range.contains(offset)
            }
            if !hasSelection {
                selectionManager.setSelectedRange(NSRange(location: offset, length: 0))
            }
        }
    }
}
