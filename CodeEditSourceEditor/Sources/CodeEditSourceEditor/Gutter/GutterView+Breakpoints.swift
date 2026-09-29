//
//  GutterView+Breakpoints.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit Developer on 9/21/26.
//

import AppKit
import CodeEditTextView

extension GutterView {
    /// Draws breakpoint markers in the leading breakpoint lane, limited to a drawing rect.
    ///
    /// Lines in ``breakpointLines`` get a blue Xcode-style arrow. If a line also matches ``currentDebugLine``, a
    /// green arrow is drawn instead to indicate the current debug execution position.
    /// - Parameters:
    ///   - context: The drawing context to draw in.
    ///   - dirtyRect: A rect to draw in, received from ``draw(_:)``.
    func drawBreakpoints(_ context: CGContext, dirtyRect: NSRect) {
        guard let textView = textView, !breakpointLines.isEmpty || currentDebugLine != nil else { return }
        context.saveGState()
        context.clip(to: dirtyRect)

        for linePosition in textView.layoutManager.linesStartingAt(dirtyRect.minY, until: dirtyRect.maxY) {
            let isCurrentDebugLine = linePosition.index == currentDebugLine
            guard isCurrentDebugLine || breakpointLines.contains(linePosition.index) else {
                continue
            }

            let fragment: LineFragment? = linePosition.data.lineFragments.first?.data
            let lineHeight = fragment?.height ?? CGFloat(fontLineHeight)
            let arrowHeight = min(10, lineHeight - 1)
            let arrowWidth: CGFloat = 8
            let arrowX = backgroundEdgeInsets.leading + max(0, (breakpointLaneWidth - arrowWidth) / 2)
            let arrowY = linePosition.yPos + (lineHeight - arrowHeight) / 2

            let arrowRect = NSRect(x: arrowX, y: arrowY, width: arrowWidth, height: arrowHeight)

            context.setFillColor(isCurrentDebugLine ? NSColor.systemGreen.cgColor : NSColor.systemBlue.cgColor)
            context.addPath(breakpointArrowPath(in: arrowRect))
            context.fillPath()
        }
        context.restoreGState()
    }

    /// Creates a right-pointing breakpoint arrow (chevron with a flat trailing edge) in the given rect.
    /// - Parameter rect: The rect to fit the arrow in.
    /// - Returns: A path containing the arrow shape.
    func breakpointArrowPath(in rect: NSRect) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.closeSubpath()
        return path
    }

    /// Handles a mouse down event in the gutter, resolving the clicked line and notifying the delegate.
    ///
    /// Any click in the gutter's line number area toggles the line (matching Xcode's behavior, where clicking a line
    /// number also toggles its breakpoint).
    /// - Parameter event: The mouse event to handle.
    func handleGutterClick(_ event: NSEvent) {
        let clickPoint = convert(event.locationInWindow, from: nil)
        guard event.type == .leftMouseDown,
              let lineIndex = textView?.layoutManager.textLineForPosition(clickPoint.y)?.index else {
            super.mouseDown(with: event)
            return
        }
        delegate?.gutterView(self, didClickLine: lineIndex)
    }
}
