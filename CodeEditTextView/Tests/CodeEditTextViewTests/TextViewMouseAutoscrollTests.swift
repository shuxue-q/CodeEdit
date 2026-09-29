//
//  TextViewMouseAutoscrollTests.swift
//  CodeEditTextView
//
//  Created by CodeEdit on 9/27/26.
//

import AppKit
import Testing
@testable import CodeEditTextView

@Suite
@MainActor
struct TextViewMouseAutoscrollTests {
    @Test
    func stationaryOutsideDragKeepsAutoscrolling() throws {
        let textView = TextView(string: (0..<80).map { "line \($0)" }.joined(separator: "\n"))
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 160))
        let window = NSWindow(
            contentRect: scrollView.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        scrollView.documentView = textView
        textView.updateFrameIfNeeded()
        textView.layoutManager.layoutLines(in: textView.bounds)

        let middleLine = try #require(textView.layoutManager.textLineForIndex(40))
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: middleLine.yPos))
        let start = NSPoint(x: 40, y: textView.visibleRect.minY + 40)
        let outside = NSPoint(x: 40, y: textView.visibleRect.maxY + 40)

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

        textView.mouseDown(with: try event(.leftMouseDown, at: start))
        textView.mouseDragged(with: try event(.leftMouseDragged, at: outside))
        let visibleTopAfterDrag = textView.visibleRect.minY
        let selectionAfterDrag = try #require(textView.selectionManager.textSelections.first?.range)

        let deadline = Date().addingTimeInterval(0.2)
        while textView.visibleRect.minY <= visibleTopAfterDrag && Date() < deadline {
            RunLoop.main.run(mode: .eventTracking, before: deadline)
        }

        #expect(textView.visibleRect.minY > visibleTopAfterDrag)
        #expect(textView.selectionManager.textSelections.first?.range.max ?? 0 > selectionAfterDrag.max)
        textView.mouseUp(with: try event(.leftMouseUp, at: outside))
    }
}
