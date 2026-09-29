//
//  LSPSignatureHelpCoordinator.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/29/26.
//

import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import LanguageServerProtocol

/// Shows the language server's parameter hints (`textDocument/signatureHelp`) above the call being
/// edited.
///
/// Hints are requested when a snippet placeholder becomes active (for example after accepting a
/// function completion, or pressing Tab to reach the next argument) and when the user types one of
/// the server's signature-help trigger characters, such as `(` or `,`. While the tooltip is open it
/// follows edits and cursor moves, and closes when the server has no signature for the cursor
/// position, on Escape, when the snippet session ends, or when the editor loses focus.
@MainActor
final class LSPSignatureHelpCoordinator {
    /// Coalesces the requests caused by a single edit (text change, then selection change).
    private static let requestDelay: Duration = .milliseconds(40)
    /// How far back to look for the call's opening parenthesis when positioning the tooltip.
    private static let anchorSearchLimit = 2_000

    private weak var document: CodeFileDocument?
    private weak var controller: TextViewController?

    @LazyService private var lspService: LSPService

    private var window: LSPSignatureHelpWindow?
    private var requestTask: Task<Void, Never>?
    private var eventMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    /// The document offset the tooltip is positioned over.
    private var anchorOffset: Int?

    init(document: CodeFileDocument) {
        self.document = document
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        requestTask?.cancel()
    }

    private var isVisible: Bool {
        window?.isVisible == true
    }

    // MARK: - Requests

    private func scheduleRequest() {
        requestTask?.cancel()
        requestTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.requestDelay)
            } catch {
                return
            }
            await self?.performRequest()
        }
    }

    private func performRequest() async {
        guard let document,
              let fileURL = document.fileURL,
              let uri = document.languageServerURI,
              let controller,
              controller.view.window?.isKeyWindow == true,
              let offset = controller.textView.selectionManager.textSelections.first?.range.location,
              let client = lspService.languageClient(forDocument: fileURL),
              client.serverCapabilities.signatureHelpProvider != nil,
              let position = controller.textView.lspPositionFrom(offset: offset) else {
            dismiss()
            return
        }
        do {
            try await document.languageServerObjects.textCoordinator.flushPendingChanges()
            try Task.checkCancellation()
            let help = try await client.requestSignatureHelp(for: uri, position)
            try Task.checkCancellation()
            guard let help, let content = LSPSignatureHelpContent(help: help) else {
                dismiss()
                return
            }
            show(content, cursorOffset: offset)
        } catch is CancellationError {
            return
        } catch {
            dismiss()
        }
    }

    /// Whether the character just before the cursor should open the tooltip.
    private func cursorFollowsTriggerCharacter() -> Bool {
        guard let controller,
              let offset = controller.textView.selectionManager.textSelections.first?.range.location,
              offset > 0,
              let fileURL = document?.fileURL,
              let options = lspService.languageClient(forDocument: fileURL)?.serverCapabilities.signatureHelpProvider
        else {
            return false
        }
        let triggers = Set((options.triggerCharacters ?? []) + (options.retriggerCharacters ?? []))
        let string = controller.textView.textStorage.string as NSString
        let previous = string.substring(with: string.rangeOfComposedCharacterSequence(at: offset - 1))
        return triggers.contains(previous)
    }

    // MARK: - Tooltip

    private func show(_ content: LSPSignatureHelpContent, cursorOffset: Int) {
        guard let controller, let parentWindow = controller.view.window else { return }
        let window = self.window ?? LSPSignatureHelpWindow(content: content, font: controller.font)
        window.update(content: content, font: controller.font)
        if window.parent !== parentWindow {
            window.parent?.removeChildWindow(window)
            parentWindow.addChildWindow(window, ordered: .above)
        }
        self.window = window
        anchorOffset = Self.callStart(before: cursorOffset, in: controller.textView.textStorage.string as NSString)
            ?? cursorOffset
        reposition()
        window.orderFront(nil)
    }

    /// Places the tooltip above the line holding the call, aligned with the start of the call.
    private func reposition() {
        guard let window,
              let controller,
              let anchorOffset,
              let parentWindow = controller.view.window,
              let textView = controller.textView,
              let lineRect = textView.layoutManager.rectForOffset(anchorOffset) else {
            return
        }
        guard textView.visibleRect.intersects(lineRect) else {
            window.orderOut(nil)
            return
        }
        let screenRect = parentWindow.convertToScreen(textView.convert(lineRect, to: nil))
        let size = window.frame.size
        var origin = NSPoint(
            x: screenRect.minX - LSPSignatureHelpView.horizontalPadding,
            y: screenRect.maxY + 2
        )
        if let screenFrame = parentWindow.screen?.visibleFrame {
            if origin.y + size.height > screenFrame.maxY {
                origin.y = screenRect.minY - size.height - 2
            }
            origin.x = min(max(origin.x, screenFrame.minX), screenFrame.maxX - size.width)
        }
        window.setFrameOrigin(origin)
        if !window.isVisible {
            window.orderFront(nil)
        }
    }

    private func dismiss() {
        requestTask?.cancel()
        requestTask = nil
        anchorOffset = nil
        if let window {
            window.parent?.removeChildWindow(window)
            window.orderOut(nil)
        }
    }

    /// The start of the function name before the innermost unclosed `(` preceding `offset`.
    static func callStart(before offset: Int, in string: NSString) -> Int? {
        var depth = 0
        var index = min(offset, string.length) - 1
        let lowerBound = max(0, offset - anchorSearchLimit)
        while index >= lowerBound {
            switch string.character(at: index) {
            case 0x29: // )
                depth += 1
            case 0x28: // (
                if depth == 0 {
                    var start = index
                    while start > 0,
                          let scalar = Unicode.Scalar(string.character(at: start - 1)),
                          LSPCompletionProvider.wordCharacters.contains(scalar) || scalar == ":" {
                        start -= 1
                    }
                    return start
                }
                depth -= 1
            case 0x3B, 0x7B, 0x7D: // ; { }
                return nil
            default:
                break
            }
            index -= 1
        }
        return nil
    }

    // MARK: - Event Handling

    private func handle(event: NSEvent) {
        guard isVisible else { return }
        switch event.type {
        case .keyDown where event.keyCode == 53: // Escape
            dismiss()
        case .leftMouseDown, .rightMouseDown:
            if event.window !== controller?.view.window {
                dismiss()
            }
        default:
            break
        }
    }
}

// MARK: - TextViewCoordinator

extension LSPSignatureHelpCoordinator: @MainActor TextViewCoordinator {
    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event: event)
            }
            return event
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: TextViewController.scrollPositionDidUpdateNotification,
            object: controller,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reposition()
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, (notification.object as? NSWindow) === self.controller?.view.window else { return }
                self.dismiss()
            }
        })
    }

    func textViewDidChangeText(controller: TextViewController) {
        if isVisible || cursorFollowsTriggerCharacter() {
            scheduleRequest()
        }
    }

    func textViewDidChangeSelection(controller: TextViewController, newPositions: [CursorPosition]) {
        if isVisible {
            scheduleRequest()
        }
    }

    func textViewDidChangeSnippetPlaceholder(controller: TextViewController, activeRanges: [NSRange]?) {
        if activeRanges == nil {
            dismiss()
        } else {
            scheduleRequest()
        }
    }

    func controllerDidDisappear(controller: TextViewController) {
        dismiss()
    }

    func destroy() {
        dismiss()
        window = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        controller = nil
    }
}
