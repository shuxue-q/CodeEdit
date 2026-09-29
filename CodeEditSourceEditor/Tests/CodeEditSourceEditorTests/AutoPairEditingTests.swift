import XCTest
@testable import CodeEditSourceEditor
import AppKit

/// Tests bracket/quote auto-closing and overtyping when typing character by character.
final class AutoPairEditingTests: XCTestCase {
    var controller: TextViewController!
    var window: NSWindow!

    override func setUpWithError() throws {
        controller = Mock.textViewController(theme: Mock.theme())
        let tsClient = Mock.treeSitterClient(forceSync: true)
        controller.treeSitterClient = tsClient
        controller.highlightProviders = [tsClient]
        window = NSWindow()
        window.contentViewController = controller
        controller.loadView()
        window.setFrame(NSRect(x: 0, y: 0, width: 1000, height: 1000), display: false)
    }

    private func type(_ text: String, into initial: String = "") {
        controller.setText(initial)
        let end = NSRange(location: (initial as NSString).length, length: 0)
        controller.textView.selectionManager.setSelectedRange(end)
        for char in text {
            controller.textView.insertText(String(char))
        }
    }

    func test_quoteOvertype() {
        type("std::cout << \"hello world!!\"")
        XCTAssertEqual(controller.textView.string, "std::cout << \"hello world!!\"")
    }

    func test_bracketOvertype() {
        type("int main(){\n")
        type("f(a[0], {1})")
        XCTAssertEqual(controller.textView.string, "f(a[0], {1})")
    }

    func test_singleQuoteOvertype() {
        type("x = 'a'")
        XCTAssertEqual(controller.textView.string, "x = 'a'")
    }

    func test_cppScreenshotFlow() {
        let cpp = TextViewController(
            string: "",
            language: .cpp,
            configuration: Mock.config(),
            cursorPositions: [],
            highlightProviders: [Mock.treeSitterClient(forceSync: true)]
        )
        cpp.treeSitterClient = Mock.treeSitterClient(forceSync: true)
        window.contentViewController = cpp
        cpp.loadView()
        cpp.setText("")
        cpp.textView.selectionManager.setSelectedRange(.zero)
        for char in "int main(){\nstd::cout << \"hello world!!\"" {
            if char == "\n" { cpp.textView.insertNewline(nil) } else { cpp.textView.insertText(String(char)) }
        }
        XCTAssertEqual(cpp.textView.string, "int main(){\n    std::cout << \"hello world!!\"\n}")
    }

    /// Input methods commit ASCII punctuation as marked text first, then replace the marked range.
    func test_quoteOvertypeViaMarkedText() {
        controller.setText("")
        controller.textView.selectionManager.setSelectedRange(.zero)
        func typeViaIME(_ string: String) {
            let textView = controller.textView!
            textView.setMarkedText(
                string,
                selectedRange: NSRange(location: 1, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            textView.insertText(string, replacementRange: textView.markedRange())
        }
        for char in "f(\"hi\", 'a')" { typeViaIME(String(char)) }
        XCTAssertEqual(controller.textView.string, "f(\"hi\", 'a')")
    }
}
