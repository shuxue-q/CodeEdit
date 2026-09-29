//
//  SuggestionWindowMetrics.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit Contributors on 9/27/26.
//

import CoreGraphics

/// Inputs for sizing the suggestion window from the list and the documentation panel.
struct SuggestionWindowMeasurement {
    var rowHeight: CGFloat
    var itemCount: Int
    var maxVisibleRows: CGFloat
    var verticalPadding: CGFloat
    var previewHeight: CGFloat
    var screenLimit: CGFloat

    /// The window is as tall as the taller panel, and never shorter than the list.
    ///
    /// A very long document is capped to the screen so the panel scrolls instead of covering it.
    var contentHeight: CGFloat {
        let rows = min(CGFloat(max(itemCount, 0)), maxVisibleRows)
        let listHeight = max(0, rowHeight) * rows + verticalPadding * 2
        let fitted = max(listHeight, max(0, previewHeight))
        let cap = max(listHeight, screenLimit)
        return min(fitted, cap)
    }
}
