//
//  TextView+Mouse.swift
//  CodeEditTextView
//
//  Created by Khan Winter on 9/19/23.
//

import AppKit

extension TextView {
    override public func mouseDown(with event: NSEvent) {
        // Set cursor
        let locationInView = convert(event.locationInWindow, from: nil)
        guard isSelectable,
              event.type == .leftMouseDown,
              visibleRect.contains(locationInView),
              let offset = layoutManager.textOffsetAtPoint(locationInView) else {
            super.mouseDown(with: event)
            return
        }

        if let content = layoutManager.contentRun(at: offset),
           case let .attachment(attachment) = content.data, event.clickCount < 3 {
            handleAttachmentClick(event: event, offset: offset, attachment: attachment)
            return
        }

        switch event.clickCount {
        case 1:
            handleSingleClick(event: event, offset: offset)
        case 2:
            handleDoubleClick(event: event)
        case 3:
            handleTripleClick(event: event)
        default:
            break
        }

        mouseDragAnchor = locationInView
    }

    /// Single click, if control-shift we add a cursor
    /// if shift, we extend the selection to the click location
    /// else we set the cursor
    fileprivate func handleSingleClick(event: NSEvent, offset: Int) {
        cursorSelectionMode = .character

        guard isEditable else {
            super.mouseDown(with: event)
            return
        }
        let eventFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if eventFlags == [.control, .shift] {
            unmarkText()
            selectionManager.addSelectedRange(NSRange(location: offset, length: 0))
        } else if eventFlags.contains(.shift) {
            unmarkText()
            shiftClickExtendSelection(to: offset)
        } else {
            selectionManager.setSelectedRange(NSRange(location: offset, length: 0))
            unmarkTextIfNeeded()
        }
    }

    fileprivate func handleDoubleClick(event: NSEvent) {
        cursorSelectionMode = .word

        guard !event.modifierFlags.contains(.shift) else {
            super.mouseDown(with: event)
            return
        }
        unmarkText()
        selectWord(nil)
    }

    fileprivate func handleTripleClick(event: NSEvent) {
        cursorSelectionMode = .line

        guard !event.modifierFlags.contains(.shift) else {
            super.mouseDown(with: event)
            return
        }
        unmarkText()
        selectLine(nil)
    }

    fileprivate func handleAttachmentClick(event: NSEvent, offset: Int, attachment: AnyTextAttachment) {
        switch event.clickCount {
        case 1:
            selectionManager.setSelectedRange(attachment.range)
        case 2:
            performAttachmentAction(attachment: attachment)
        default:
            break
        }
    }

    func performAttachmentAction(attachment: AnyTextAttachment) {
        let action = attachment.attachment.attachmentAction()
        switch action {
        case .none:
            return
        case .discard:
            layoutManager.attachments.remove(atOffset: attachment.range.location)
            selectionManager.setSelectedRange(NSRange(location: attachment.range.location, length: 0))
        case let .replace(text):
            replaceCharacters(in: attachment.range, with: text)
        }
    }

    override public func mouseUp(with event: NSEvent) {
        mouseDragAnchor = nil
        disableMouseAutoscrollTimer()
        super.mouseUp(with: event)
    }

    override public func mouseDragged(with event: NSEvent) {
        guard let mouseDragAnchor,
              isSelectable,
              !isDragging,
              !(inputContext?.handleEvent(event) ?? false) else {
            return
        }

        let locationInView = convert(event.locationInWindow, from: nil)
        if visibleRect.contains(locationInView) {
            disableMouseAutoscrollTimer()
        } else {
            mouseDragEvent = event
            setUpMouseAutoscrollTimer()
        }

        updateDragSelection(with: event, from: mouseDragAnchor)
        autoscroll(with: event)
    }

    private func updateDragSelection(with event: NSEvent, from mouseDragAnchor: CGPoint) {
        // Keep drag positions within the visible text while the mouse is outside the editor.
        // The document view's frame extends beyond the viewport when the file is scrolled.
        let locationInWindow = convert(event.locationInWindow, from: nil)
        let visibleBounds = visibleRect
        let locationInView = CGPoint(
            x: max(visibleBounds.minX, min(locationInWindow.x, visibleBounds.maxX)),
            y: max(visibleBounds.minY, min(locationInWindow.y, visibleBounds.maxY))
        )

        guard let startPosition = layoutManager.textOffsetAtPoint(mouseDragAnchor),
              let endPosition = layoutManager.textOffsetAtPoint(locationInView) else {
            return
        }

        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifierFlags.contains(.option) {
            selectColumns(betweenPointA: mouseDragAnchor, pointB: locationInView)
            setNeedsDisplay()
        } else {
            dragSelection(startPosition: startPosition, endPosition: endPosition)
        }
    }

    /// Extends the current selection to the offset. Only used when the user shift-clicks a location in the document.
    ///
    /// If the offset is within the selection, trims the selection from the nearest edge (start or end) towards the
    /// clicked offset.
    /// Otherwise, extends the selection to the clicked offset.
    ///
    /// - Parameter offset: The offset clicked on.
    fileprivate func shiftClickExtendSelection(to offset: Int) {
        // Use the last added selection, this is behavior copied from Xcode.
        guard var selectedRange = selectionManager.textSelections.last?.range else { return }
        if selectedRange.contains(offset) {
            if offset - selectedRange.location <= selectedRange.max - offset {
                selectedRange.length -= offset - selectedRange.location
                selectedRange.location = offset
            } else {
                selectedRange.length -= selectedRange.max - offset
            }
        } else {
            selectedRange.formUnion(NSRange(
                start: min(offset, selectedRange.location),
                end: max(offset, selectedRange.max)
            ))
        }
        selectionManager.setSelectedRange(selectedRange)
        setNeedsDisplay()
    }

    // MARK: - Mouse Autoscroll

    /// Sets up a timer that fires at a predetermined period to autoscroll the text view.
    /// Ensure the timer is disabled using ``disableMouseAutoscrollTimer``.
    func setUpMouseAutoscrollTimer() {
        guard mouseDragTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self, let event = self.mouseDragEvent, let mouseDragAnchor = self.mouseDragAnchor else { return }
            if self.autoscroll(with: event) {
                self.updateDragSelection(with: event, from: mouseDragAnchor)
            }
        }
        RunLoop.main.add(timer, forMode: .default)
        RunLoop.main.add(timer, forMode: .eventTracking)
        mouseDragTimer = timer
    }

    /// Disables the mouse drag timer started by ``setUpMouseAutoscrollTimer``
    func disableMouseAutoscrollTimer() {
        mouseDragTimer?.invalidate()
        mouseDragTimer = nil
        mouseDragEvent = nil
    }

    // MARK: - Drag Selection

    private func dragSelection(startPosition: Int, endPosition: Int) {
        switch cursorSelectionMode {
        case .character:
            setDragSelection(
                NSRange(
                    location: min(startPosition, endPosition),
                    length: max(startPosition, endPosition) - min(startPosition, endPosition)
                )
            )

        case .word:
            let startWordRange = findWordBoundary(at: startPosition)
            let endWordRange = findWordBoundary(at: endPosition)

            setDragSelection(
                NSRange(
                    location: min(startWordRange.location, endWordRange.location),
                    length: max(
                        startWordRange.location + startWordRange.length,
                        endWordRange.location + endWordRange.length
                    ) -
                    min(startWordRange.location, endWordRange.location)
                )
            )

        case .line:
            let startLineRange = findLineBoundary(at: startPosition)
            let endLineRange = findLineBoundary(at: endPosition)

            setDragSelection(
                NSRange(
                    location: min(startLineRange.location, endLineRange.location),
                    length: max(
                        startLineRange.location + startLineRange.length,
                        endLineRange.location + endLineRange.length
                    ) -
                    min(startLineRange.location, endLineRange.location)
                )
            )
        }
    }

    private func setDragSelection(_ range: NSRange) {
        if selectionManager.textSelections.count == 1, selectionManager.textSelections[0].range == range {
            return
        }
        selectionManager.setSelectedRange(range)
        setNeedsDisplay()
    }

}
