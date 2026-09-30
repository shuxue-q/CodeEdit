import XCTest
import AppKit
import CodeEditTextView
import CodeEditLanguages
@testable import CodeEditSourceEditor

/// Regression tests for text inserted past the old end of the document keeping stale (plain) attributes after an edit,
/// e.g. accepting `CMAKE_EXPORT_COMPILE_COMMANDS` after typing `CMAKE_` near the end of a `CMakeLists.txt`.
final class HighlighterEditVisibilityTests: XCTestCase {
    private let source = "cmake_minimum_required(VERSION 3.20)\nproject(Demo)\nset(CMAKE_)\n"
    private let completed = "CMAKE_EXPORT_COMPILE_COMMANDS"

    @MainActor
    private func makeController() -> (TextViewController, NSWindow) {
        let controller = TextViewController(
            string: source,
            language: .cmake,
            configuration: Mock.config(),
            cursorPositions: [],
            highlightProviders: [TreeSitterClient()]
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        controller.view.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        controller.view.layoutSubtreeIfNeeded()
        return (controller, window)
    }

    @MainActor
    private func waitForHighlights() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    }

    @MainActor
    private func colors(in controller: TextViewController, range: NSRange) -> [NSColor?] {
        (range.location..<range.max).map {
            controller.textView.textStorage.attribute(.foregroundColor, at: $0, effectiveRange: nil) as? NSColor
        }
    }

    @MainActor
    func test_replacementGrowingPastOldDocumentEndIsFullyHighlighted() {
        let (controller, window) = makeController()
        defer { window.close() }
        waitForHighlights()

        let prefixRange = (source as NSString).range(of: "CMAKE_")
        let constantColor = controller.attributesFor(.constant)[.foregroundColor] as? NSColor
        XCTAssertEqual(Set(colors(in: controller, range: prefixRange)), [constantColor])

        // Same edit the completion delegate makes: replace the typed prefix with the full item.
        controller.textView.replaceCharacters(in: prefixRange, with: completed)
        waitForHighlights()

        let tokenRange = NSRange(location: prefixRange.location, length: (completed as NSString).length)
        XCTAssertEqual(Set(colors(in: controller, range: tokenRange)), [constantColor])
    }
}
