//
//  TextViewDragSelectionFillTests.swift
//  CodeEditTextViewTests
//
//  Created by CodeEdit Contributors on 9/30/26.
//

import Testing
import AppKit
@testable import CodeEditTextView

@Suite
@MainActor
struct TextViewDragSelectionFillTests {
    /// Dragging up from the empty last line selects every line in between. The line above the empty last line ends
    /// with the document's final line break; its fill rect must still cover the whole line.
    @Test
    func upwardDragFromEmptyLastLineFillsIntermediateLines() throws {
        let textView = TextView(string: "project(demo)\nset(EXPORT ON)\nset(EXPORT ON)\n")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = textView
        textView.layoutManager.layoutLines(in: textView.bounds)

        func event(_ type: NSEvent.EventType, at point: NSPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(
                with: type,
                location: textView.convert(point, to: nil),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ))
        }

        // Outside a scroll view the text view sizes itself to its content, so draw into a fixed rect.
        let drawRect = NSRect(x: 0, y: 0, width: 800, height: 600)
        let emptyLine = try #require(textView.layoutManager.textLineForIndex(3))
        #expect(emptyLine.range.isEmpty)
        let start = NSPoint(x: 20, y: emptyLine.yPos + emptyLine.height / 2)
        textView.mouseDown(with: try event(.leftMouseDown, at: start))

        for (targetIndex, filledLines) in [(2, [2]), (1, [1, 2])] {
            let target = try #require(textView.layoutManager.textLineForIndex(targetIndex))
            let targetRect = try #require(textView.layoutManager.rectForOffset(target.range.location + 3))
            let point = NSPoint(x: targetRect.minX + 1, y: targetRect.midY)
            let targetOffset = try #require(textView.layoutManager.textOffsetAtPoint(point))
            textView.mouseDragged(with: try event(.leftMouseDragged, at: point))

            let selection = try #require(textView.selectionManager.textSelections.first)
            let expected = NSRange(location: targetOffset, length: textView.textStorage.length - targetOffset)
            #expect(selection.range == expected)

            let fillRects = textView.selectionManager.getFillRects(in: drawRect, for: selection)
            for lineIndex in filledLines {
                let line = try #require(textView.layoutManager.textLineForIndex(lineIndex))
                let lineRects = fillRects.filter { $0.midY > line.yPos && $0.midY < line.yPos + line.height }
                let lineEnd = try #require(textView.layoutManager.rectForOffset(line.range.max - 1))
                // Each selected line is filled past its last character, through the line break.
                #expect(lineRects.contains { $0.maxX > lineEnd.maxX }, "line \(lineIndex) is not filled")
            }
        }

        textView.mouseUp(with: try event(.leftMouseUp, at: start))
    }
}
