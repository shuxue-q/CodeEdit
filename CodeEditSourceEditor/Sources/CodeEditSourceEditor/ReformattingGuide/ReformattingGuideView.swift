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

    /// Draws only the hint line. The editor background continues on both sides.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let isLightMode = theme.background.brightnessComponent > 0.5
        let lineColor = isLightMode
            ? NSColor.black.withAlphaComponent(0.075)
            : NSColor.white.withAlphaComponent(0.175)

        lineColor.setFill()
        bounds.fill()
    }

    func updatePosition(in controller: TextViewController) {
        // Calculate the x position based on the font's character width, letter spacing, and column number
        let leftInset = controller.textView?.layoutManager.edgeInsets.left ?? controller.textViewInsets.left
        let charAdvance = controller.font.charWidth * CGFloat(controller.letterSpacing)
        let xPosition = (
            CGFloat(column) * charAdvance
            + leftInset
        )

        guard let scrollView = controller.scrollView else { return }
        let contentSize = scrollView.documentVisibleRect.size
        let totalHeight = max(contentSize.height, scrollView.documentView?.frame.height ?? 0)

        // A 1pt line at the column. Text lays out across it; the line does not paint a second background.
        var newFrame = NSRect(
            x: xPosition,
            y: 0,
            width: 1,
            height: totalHeight
        ).pixelAligned
        newFrame.size.width = 1

        frame = newFrame
        needsDisplay = true
    }
}
