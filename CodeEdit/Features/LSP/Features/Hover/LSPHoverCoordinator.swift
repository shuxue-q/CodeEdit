//
//  LSPHoverCoordinator.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/10/26.
//

import AppKit
import SwiftUI
import CodeEditSourceEditor
import CodeEditTextView
import LanguageServerProtocol

/// Shows language-server documentation in a popover when the mouse rests over a symbol.
///
/// The coordinator installs a local event monitor on the editor's window and, after a short
/// delay without mouse movement, sends a `textDocument/hover` request for the identifier or
/// filename under the cursor. Whitespace, punctuation, and empty space on a line are ignored.
/// Any click, key press, scroll, or mouse movement dismisses the popover.
@MainActor
final class LSPHoverCoordinator {
    /// The delay between the mouse coming to rest and the hover request being sent.
    private static let hoverDelay: Duration = .milliseconds(400)

    private weak var document: CodeFileDocument?
    private weak var controller: TextViewController?

    @LazyService private var lspService: LSPService

    private var eventMonitor: Any?
    private var hoverTask: Task<Void, Never>?
    private var popover: NSPopover?
    /// The document offset the current popover (or pending request) is shown for.
    private var hoveredOffset: Int?

    init(document: CodeFileDocument) {
        self.document = document
    }

    // MARK: - TextViewCoordinator

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event: event)
            }
            return event
        }
    }

    func destroy() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        hoverTask?.cancel()
        hoverTask = nil
        popover?.close()
        popover = nil
        controller = nil
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        hoverTask?.cancel()
    }

    // MARK: - Event Handling

    private func handle(event: NSEvent) {
        let popoverWindow = popover?.contentViewController?.view.window

        // If the event is directed at the popover window or the cursor is inside it,
        // allow the user to read, scroll, and select text inside without dismissing it.
        let isOverPopover = (popoverWindow != nil && event.window === popoverWindow)
            || (popoverWindow?.frame.contains(NSEvent.mouseLocation) == true)

        if isOverPopover {
            switch event.type {
            case .mouseMoved, .scrollWheel, .leftMouseDown, .rightMouseDown, .otherMouseDown:
                return
            case .keyDown:
                // Dismiss only if the user pressed the Escape key.
                if event.keyCode == 53 {
                    dismiss()
                }
                return
            default:
                return
            }
        }

        // For events outside the popover window, dismiss on click, key press, or scroll.
        guard event.type == .mouseMoved else {
            dismiss()
            return
        }
        guard let controller,
              let textView = controller.textView,
              event.window === controller.view.window,
              event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask) else {
            dismiss()
            return
        }

        let point = textView.convert(event.locationInWindow, from: nil)
        guard let offset = hoverableOffset(in: textView, at: point) else {
            dismiss()
            return
        }

        guard offset != hoveredOffset else { return }
        scheduleHover(at: offset)
    }

    /// Returns a document offset only when the pointer is on an identifier or filename glyph.
    private func hoverableOffset(in textView: TextView, at point: NSPoint) -> Int? {
        guard textView.visibleRect.contains(point),
              let offset = textView.layoutManager.textOffsetAtPoint(point),
              offset < textView.textStorage.length else {
            return nil
        }

        let string = textView.textStorage.string as NSString
        guard LSPHoverTrigger.shouldRequestHover(at: offset, in: string) else {
            return nil
        }
        if let glyphRect = textView.layoutManager.rectForOffset(offset),
           !LSPHoverTrigger.glyphContainsMouse(point: point, glyphRect: glyphRect) {
            return nil
        }
        return offset
    }

    /// Cancels any pending request or visible popover.
    private func dismiss() {
        hoverTask?.cancel()
        hoverTask = nil
        hoveredOffset = nil
        popover?.close()
        popover = nil
    }

    // MARK: - Hover Request

    private func scheduleHover(at offset: Int) {
        hoverTask?.cancel()
        hoverTask = Task {
            do {
                try await Task.sleep(for: Self.hoverDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            // Do not override an open popover if the mouse is currently inside it
            if let popoverWindow = popover?.contentViewController?.view.window,
               popoverWindow.frame.contains(NSEvent.mouseLocation) {
                return
            }
            await performHover(at: offset)
        }
    }

    private func performHover(at offset: Int) async {
        guard let document,
              let fileURL = document.fileURL,
              let uri = document.languageServerURI,
              let controller,
              let position = controller.textView.lspPositionFrom(offset: offset) else {
            return
        }
        let client = lspService.languageClient(forDocument: fileURL)
        guard let client, client.supportsHover else { return }

        do {
            guard let hover = try await client.requestHover(for: uri, position) else { return }
            let content = hoverContent(from: hover)
            guard !Task.isCancelled, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            showPopover(content: content, at: offset, hoverRange: hover.range, in: controller)
        } catch {
            return
        }
    }

    // MARK: - Popover

    private func showPopover(
        content: String,
        at offset: Int,
        hoverRange: LSPRange?,
        in controller: TextViewController
    ) {
        guard let textView = controller.textView else { return }
        var rect: NSRect?
        if let hoverRange, let nsRange = textView.nsRangeFrom(lspRange: hoverRange) {
            rect = textView.layoutManager.rectForOffset(nsRange.location)
        }
        guard let positioningRect = rect ?? textView.layoutManager.rectForOffset(offset) else { return }

        hoveredOffset = offset

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let hoverView = LSPHoverView(content: content, language: document?.language) { [weak popover] newHeight in
            guard let popover else { return }
            let clampedHeight = min(max(newHeight, LSPHoverView.minHeight), LSPHoverView.maxHeight)
            if popover.contentSize.height != clampedHeight {
                popover.contentSize = NSSize(width: LSPHoverView.popoverWidth, height: clampedHeight)
            }
        }
        let hostingController = NSHostingController(rootView: hoverView)
        hostingController.view.layoutSubtreeIfNeeded()
        let fitting = hostingController.view.fittingSize
        let initialHeight = min(
            max(fitting.height > 0 ? fitting.height : hoverView.documentation.estimatedHeight, LSPHoverView.minHeight),
            LSPHoverView.maxHeight
        )
        popover.contentSize = NSSize(width: LSPHoverView.popoverWidth, height: initialHeight)
        popover.contentViewController = hostingController
        self.popover?.close()
        popover.show(relativeTo: positioningRect, of: textView, preferredEdge: .maxY)
        self.popover = popover
    }

    // MARK: - Content Parsing

    /// Extracts a displayable string from a hover response's contents.
    private func hoverContent(from hover: Hover) -> String {
        switch hover.contents {
        case .optionA(let markedString):
            return markedStringContent(markedString)
        case .optionB(let markedStrings):
            return markedStrings.map(markedStringContent).joined(separator: "\n\n")
        case .optionC(let markupContent):
            return markupContent.value
        }
    }

    private func markedStringContent(_ markedString: MarkedString) -> String {
        switch markedString {
        case .optionA(let string):
            return string
        case .optionB(let pair):
            let lang = pair.language.rawValue.trimmingCharacters(in: .whitespaces)
            return "```\(lang)\n\(pair.value)\n```"
        }
    }
}

// The conformance is isolated to the main actor, matching this class's isolation.
extension LSPHoverCoordinator: @MainActor TextViewCoordinator { }

private extension LanguageServer {
    /// Whether the server advertised hover support.
    var supportsHover: Bool {
        switch serverCapabilities.hoverProvider {
        case .optionA(let supported):
            return supported
        case .optionB:
            return true
        case nil:
            return false
        }
    }
}
