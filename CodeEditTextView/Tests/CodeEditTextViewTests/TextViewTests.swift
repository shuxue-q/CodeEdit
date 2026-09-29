import Testing
import AppKit
@testable import CodeEditTextView

@Suite
@MainActor
struct TextViewTests {
    class MockDelegate: TextViewDelegate {
        var shouldReplaceContents: ((_ textView: TextView, _ range: NSRange, _ string: String) -> Bool)?

        func textView(_ textView: TextView, shouldReplaceContentsIn range: NSRange, with string: String) -> Bool {
            shouldReplaceContents?(textView, range, string) ?? true
        }
    }

    let textView: TextView
    let delegate: MockDelegate

    init() {
        textView = TextView(string: "Lorem Ipsum")
        delegate = MockDelegate()
        textView.delegate = delegate
    }

    /// Bracket-pair deletion runs from `shouldReplaceContentsIn`, deletes the pair, and parks
    /// the caret at the new end of the string. Line storage has to observe that deletion before
    /// the caret rect is calculated.
    @Test
    func filterDeleteAtEndKeepsLineStorageInSync() {
        let textView = TextView(string: "hello()")
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        let delegate = MockDelegate()
        textView.delegate = delegate
        delegate.shouldReplaceContents = { textView, _, _ in
            let length = textView.textStorage.length
            textView.textStorage.replaceCharacters(in: NSRange(location: length - 2, length: 2), with: "")
            textView.selectionManager.setSelectedRange(NSRange(location: textView.textStorage.length, length: 0))
            return false
        }

        textView.replaceCharacters(in: NSRange(location: textView.textStorage.length - 1, length: 1), with: "")

        #expect(textView.string == "hello")
        #expect(textView.selectionManager.textSelections.first?.range == NSRange(location: 5, length: 0))
        #expect(textView.layoutManager.lineStorage.length == textView.textStorage.length)
        textView.layoutManager.layoutLines(in: textView.bounds)
        textView.layoutManager.lineStorage.validateInternalState()
    }

    @Test
    func delegateChangesText() {
        var hasReplaced = false
        delegate.shouldReplaceContents = { textView, _, _ -> Bool in
            if !hasReplaced {
                hasReplaced.toggle()
                textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: " World ")
            }

            return true
        }

        textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "Hello")

        #expect(textView.string == "Hello World Lorem Ipsum")
        // available in test module
        textView.layoutManager.lineStorage.validateInternalState()
    }

    @Test
    func sharedTextStorage() {
        let storage = NSTextStorage(string: "Hello world")

        let textView1 = TextView(string: "")
        textView1.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        textView1.layoutSubtreeIfNeeded()
        textView1.setTextStorage(storage)

        let textView2 = TextView(string: "")
        textView2.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        textView2.layoutSubtreeIfNeeded()
        textView2.setTextStorage(storage)

        // Expect both text views to receive edited events from the storage
        #expect(textView1.layoutManager.lineCount == 1)
        #expect(textView2.layoutManager.lineCount == 1)

        storage.replaceCharacters(in: NSRange(location: 11, length: 0), with: "\nMore Lines\n")

        #expect(textView1.layoutManager.lineCount == 3)
        #expect(textView2.layoutManager.lineCount == 3)
    }

    @Test("Custom UndoManager class receives events")
    func customUndoManagerReceivesEvents() {
        let textView = TextView(string: "")

        textView.replaceCharacters(in: .zero, with: "Hello World")
        textView.undo(nil)

        #expect(textView.string == "")

        textView.redo(nil)

        #expect(textView.string == "Hello World")
    }

    @Test
    func upwardDragSelectsFromMouseDownAcrossLines() throws {
        let textView = TextView(string: "one\ntwo\nthree\nfour\nfive\n")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = textView
        textView.layoutManager.layoutLines(in: textView.bounds)

        func point(onLine index: Int) throws -> NSPoint {
            let line = try #require(textView.layoutManager.textLineForIndex(index))
            let rect = try #require(textView.layoutManager.rectForOffset(line.range.location + 1))
            return NSPoint(x: rect.minX + 1, y: rect.midY)
        }

        func event(
            _ type: NSEvent.EventType,
            at point: NSPoint,
            modifiers: NSEvent.ModifierFlags = []
        ) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(
                with: type,
                location: textView.convert(point, to: nil),
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ))
        }

        let start = try point(onLine: 4)
        let first = try point(onLine: 1)
        let next = try point(onLine: 2)
        let startOffset = try #require(textView.layoutManager.textOffsetAtPoint(start))

        textView.mouseDown(with: try event(.leftMouseDown, at: start))
        textView.mouseDragged(with: try event(.leftMouseDragged, at: first))
        let firstSelection = try #require(textView.selectionManager.textSelections.first?.range)
        #expect(firstSelection.max == startOffset)
        #expect(textView.layoutManager.textLineForOffset(firstSelection.location)?.index == 1)

        textView.mouseDragged(with: try event(.leftMouseDragged, at: next))
        let nextSelection = try #require(textView.selectionManager.textSelections.first?.range)
        #expect(nextSelection.max == startOffset)
        #expect(textView.layoutManager.textLineForOffset(nextSelection.location)?.index == 2)
        textView.mouseUp(with: try event(.leftMouseUp, at: next))

        let columnEnd = NSPoint(x: first.x + 10, y: first.y)
        textView.mouseDown(with: try event(.leftMouseDown, at: start, modifiers: .option))
        textView.mouseDragged(with: try event(.leftMouseDragged, at: columnEnd, modifiers: .option))
        #expect(textView.selectionManager.textSelections.count == 4)
        textView.mouseUp(with: try event(.leftMouseUp, at: columnEnd, modifiers: .option))
    }

    @Test
    func gutterDragSelectsEachLineWithTextInset() throws {
        let textView = TextView(string: "zero\none\ntwo\nthree\nfour\nfive\n")
        textView.textInsets = HorizontalEdgeInsets(left: 80, right: 0)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 160),
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

        let startLine = try #require(textView.layoutManager.textLineForIndex(1))
        let startRect = try #require(textView.layoutManager.rectForOffset(startLine.range.location + 1))
        let start = NSPoint(x: startRect.minX + 1, y: startRect.midY)
        let startOffset = try #require(textView.layoutManager.textOffsetAtPoint(start))
        textView.mouseDown(with: try event(.leftMouseDown, at: start))

        for (lineIndex, xPos) in [(2, 40.0), (3, -200.0), (4, 40.0)] {
            let line = try #require(textView.layoutManager.textLineForIndex(lineIndex))
            let point = NSPoint(x: xPos, y: line.yPos + line.height / 2)
            textView.mouseDragged(with: try event(.leftMouseDragged, at: point))
            let selection = try #require(textView.selectionManager.textSelections.first?.range)
            #expect(selection.location == startOffset)
            #expect(selection.max == line.range.location)
        }

        textView.mouseUp(with: try event(.leftMouseUp, at: start))
    }

    @Test
    func upwardDragOutsideScrolledEditorSelectsVisibleTopLine() throws {
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

        let visibleTop = textView.visibleRect.minY
        let start = NSPoint(x: 30, y: visibleTop + 100)
        let outside = NSPoint(x: -40, y: visibleTop - 40)
        let topOffset = try #require(textView.layoutManager.textOffsetAtPoint(NSPoint(x: 0, y: visibleTop)))
        let startOffset = try #require(textView.layoutManager.textOffsetAtPoint(start))

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
        let selection = try #require(textView.selectionManager.textSelections.first?.range)
        #expect(selection.location == topOffset)
        #expect(selection.max == startOffset)

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: visibleTop - 60))
        let newVisibleTop = textView.visibleRect.minY
        #expect(newVisibleTop < visibleTop)
        let newOutside = NSPoint(x: outside.x, y: newVisibleTop - 40)
        let newTopOffset = try #require(textView.layoutManager.textOffsetAtPoint(
            NSPoint(x: 0, y: newVisibleTop)
        ))
        textView.mouseDragged(with: try event(.leftMouseDragged, at: newOutside))
        let extendedSelection = try #require(textView.selectionManager.textSelections.first?.range)
        #expect(extendedSelection.location == newTopOffset && textView.selectionManager.textSelections.count == 1)
        #expect(extendedSelection.location < selection.location)
        #expect(extendedSelection.max == startOffset)
        textView.mouseUp(with: try event(.leftMouseUp, at: newOutside))
    }

    @Test
    func outsideMouseDownDoesNotStartSelection() throws {
        let textView = TextView(string: "one\ntwo\nthree\n")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 160),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = textView
        textView.layoutManager.layoutLines(in: textView.bounds)

        let line = try #require(textView.layoutManager.textLineForIndex(1))
        let rect = try #require(textView.layoutManager.rectForOffset(line.range.location + 1))
        let inside = NSPoint(x: rect.minX + 1, y: rect.midY)
        let outside = NSPoint(x: -40, y: inside.y)
        let originalSelections = textView.selectionManager.textSelections.map(\.range)

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

        textView.mouseDown(with: try event(.leftMouseDown, at: outside))
        #expect(textView.mouseDragAnchor == nil)
        textView.mouseDragged(with: try event(.leftMouseDragged, at: inside))
        #expect(textView.mouseDragAnchor == nil)
        #expect(textView.selectionManager.textSelections.map(\.range) == originalSelections)
        textView.mouseUp(with: try event(.leftMouseUp, at: inside))
    }
}
