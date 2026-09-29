//
//  SuggestionListLayout.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit Contributors on 9/27/26.
//

import AppKit
import SwiftUI

/// Row and list measurements that stay stable while the selection moves.
enum SuggestionListLayout {
    private static var rowHeights: [String: CGFloat] = [:]

    static func listWidth(items: [CodeSuggestionEntry], font: NSFont) -> CGFloat {
        let maxLength = min(
            items.reduce(0) { max($0, $1.label.count + ($1.detail?.count ?? 0)) } + 4,
            64
        )
        // Minimum width is 256. Horizontal item padding is 13 on each side.
        return max(CGFloat(maxLength) * font.charWidth + 26, 256)
    }

    /// One row, measured off the table. A live row's fitting size grows to the window while arrowing.
    static func rowHeight(font: NSFont, sample: CodeSuggestionEntry?) -> CGFloat {
        let key = "\(font.fontName)-\(font.pointSize)"
        if let cached = rowHeights[key] {
            return cached
        }
        let measured = measure(font: font, sample: sample)
        rowHeights[key] = measured
        return measured
    }

    static func screenLimit(height: CGFloat?) -> CGFloat {
        max(160, (height ?? 700) - 40)
    }

    static func apply(rowHeight: CGFloat, to tableView: NSTableView) {
        guard tableView.rowHeight != rowHeight else { return }
        tableView.rowHeight = rowHeight
        guard tableView.numberOfRows > 0 else { return }
        tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<tableView.numberOfRows))
    }

    private static func measure(font: NSFont, sample: CodeSuggestionEntry?) -> CGFloat {
        let fallback = ceil(font.lineHeight) + 8
        guard let sample else { return fallback }
        let host = NSHostingView(rootView: CodeSuggestionLabelView(
            suggestion: sample,
            labelColor: .labelColor,
            secondaryLabelColor: .secondaryLabelColor,
            font: font
        ))
        host.sizingOptions = .intrinsicContentSize
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 1)
        host.layoutSubtreeIfNeeded()
        let height = host.fittingSize.height
        return height >= 8 ? ceil(height) : fallback
    }
}
