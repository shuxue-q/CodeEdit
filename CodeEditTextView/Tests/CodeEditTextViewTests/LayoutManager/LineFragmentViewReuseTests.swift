import Testing
import AppKit
@testable import CodeEditTextView

@Suite
@MainActor
struct LineFragmentViewReuseTests {
    @Test
    func returnAtEndOfClosingBraceKeepsLineView() throws {
        let source = "int main() {\n    return exit_code;\n}\n"
        let textView = TextView(string: source)
        textView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        textView.layoutSubtreeIfNeeded()
        let layoutManager = try #require(textView.layoutManager)
        layoutManager.layoutLines(in: textView.bounds)

        let brace = (source as NSString).range(of: "}").location
        let braceLine = try #require(layoutManager.textLineForOffset(brace))
        let key = TextLayoutManager.LineFragmentViewKey(lineID: braceLine.data.id, fragmentIndex: 0)
        let view = try #require(layoutManager.viewReuseQueue.getView(forKey: key))

        textView.selectionManager.setSelectedRange(NSRange(location: brace + 1, length: 0))
        textView.insertNewline(nil)
        layoutManager.layoutLines(in: textView.bounds)

        let updatedLine = try #require(layoutManager.textLineForOffset(brace))
        let updatedKey = TextLayoutManager.LineFragmentViewKey(lineID: updatedLine.data.id, fragmentIndex: 0)
        let updatedView = try #require(layoutManager.viewReuseQueue.getView(forKey: updatedKey))

        #expect(updatedView === view)
        #expect(updatedView.isHidden == false)
        #expect(updatedView.lineFragment != nil)
        #expect(textView.string.contains("}"))
    }
}
