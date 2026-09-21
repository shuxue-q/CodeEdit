//
//  ReformattingGuideView.swift
//  CodeEditSourceEditor
//
//  Created by Austin Condiff on 4/28/25.
//

import AppKit
import CodeEditTextView

class ReformattingGuideView: NSView {
    @Invalidating(.display)
    var column: Int = 80

    var theme: EditorTheme {
        didSet { needsDisplay = true }
    }

    convenience init(configuration: borrowing SourceEditorConfiguration) {
        self.init(
            column: configuration.behavior.reformatAtColumn,
            theme: configuration.appearance.theme
        )
    }

    init(column: Int = 80, theme: EditorTheme) {
        self.column = column
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    // Draw the reformatting guide line and shaded area
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Determine if we should use light or dark colors based on the theme's background color
        let isLightMode = theme.background.brightnessComponent > 0.5

        // Set the line color based on the theme
        let lineColor = isLightMode ?
            NSColor.black.withAlphaComponent(0.075) :
            NSColor.white.withAlphaComponent(0.175)

        // Set the shaded area color (slightly more transparent)
        let shadedColor = isLightMode ?
            NSColor.black.withAlphaComponent(0.025) :
            NSColor.white.withAlphaComponent(0.025)

        // Draw the shaded area to the right of the line
        shadedColor.setFill()
        let shadedRect = NSRect(
            x: bounds.minX,
            y: bounds.minY,
            width: bounds.width,
            height: bounds.height
        )
        shadedRect.fill()

        // Draw the vertical line (accounting for inverted Y coordinate system)
        lineColor.setStroke()
        let linePath = NSBezierPath()
        linePath.move(to: NSPoint(x: bounds.minX + 0.5, y: bounds.maxY))  // Start at top
        linePath.line(to: NSPoint(x: bounds.minX + 0.5, y: bounds.minY))  // Draw down to bottom
        linePath.lineWidth = 1.0
        linePath.stroke()
    }

    func updatePosition(in controller: TextViewController) {
        // Calculate the x position based on the font's character width, letter spacing, and column number
        let leftInset = controller.textView?.layoutManager.edgeInsets.left ?? controller.textViewInsets.left
        let charAdvance = controller.font.charWidth * CGFloat(controller.letterSpacing)
        let xPosition = (
            CGFloat(column) * charAdvance
            + leftInset
        )

        // Get the scroll view's content size
        guard let scrollView = controller.scrollView else { return }
        let contentSize = scrollView.documentVisibleRect.size

        // Ensure the frame has at least 1.0 width so the vertical line is always renderable,
        // and cover the full document/visible width to the right of the line.
        let totalWidth = max(
            scrollView.documentVisibleRect.maxX,
            scrollView.documentView?.frame.width ?? 0,
            contentSize.width
        )
        let maxWidth = max(1.0, totalWidth - xPosition)
        let totalHeight = max(contentSize.height, scrollView.documentView?.frame.height ?? 0)

        // Update the frame to be a vertical line at the specified column with a shaded area to the right
        let newFrame = NSRect(
            x: xPosition,
            y: 0,
            width: maxWidth,
            height: totalHeight
        ).pixelAligned

        frame = newFrame
        needsDisplay = true
    }
}
