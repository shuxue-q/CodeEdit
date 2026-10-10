import XCTest
import CodeEditLanguages
import CodeEditTextView
@testable import CodeEditSourceEditor

/// Verifies that the grammar queries mark the variable being written to with `variable.assigned` while variables that
/// are only read keep their plain capture.
final class AssignedVariableQueryTests: XCTestCase {
    /// Highlights for `source`, keyed by the exact range of each highlighted span.
    @MainActor
    private func highlights(in source: String, language: CodeLanguage) -> [NSRange: CaptureName] {
        let textView = Mock.textView()
        textView.setText(source)
        let client = Mock.treeSitterClient(forceSync: true)
        client.setUp(textView: textView, codeLanguage: language)
        var found: [HighlightRange] = []
        let documentRange = NSRange(location: 0, length: (source as NSString).length)
        client.queryHighlightsFor(textView: textView, range: documentRange) {
            if case .success(let ranges) = $0 { found = ranges }
        }
        XCTAssertFalse(found.isEmpty, "\(language.id) produced no highlights")
        var result: [NSRange: CaptureName] = [:]
        for highlight in found {
            guard let capture = highlight.capture, capture.bracketLevelIndex == nil else { continue }
            result[highlight.range] = capture
        }
        return result
    }

    /// The capture covering the `occurrence`-th whole-word match of `word` in `source` (`nil` when unstyled).
    private func capture(
        of word: String,
        occurrence: Int = 0,
        in source: String,
        highlights: [NSRange: CaptureName]
    ) -> CaptureName? {
        let pattern = "(?<!\\w)" + NSRegularExpression.escapedPattern(for: word) + "(?!\\w)"
        let regex = try! NSRegularExpression(pattern: pattern) // swiftlint:disable:this force_try
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: (source as NSString).length))
        guard occurrence < matches.count else {
            XCTFail("\(word) occurrence \(occurrence) not found in source")
            return nil
        }
        return highlights[matches[occurrence].range]
    }

    struct Expectation {
        let word: String
        let occurrence: Int
        let capture: CaptureName?
        let negated: Bool

        init(_ word: String, _ occurrence: Int = 0, is capture: CaptureName?) {
            self.word = word
            self.occurrence = occurrence
            self.capture = capture
            self.negated = false
        }

        init(_ word: String, _ occurrence: Int = 0, isNot capture: CaptureName) {
            self.word = word
            self.occurrence = occurrence
            self.capture = capture
            self.negated = true
        }
    }

    @MainActor
    func check(_ source: String, language: CodeLanguage, _ expectations: [Expectation]) {
        let found = highlights(in: source, language: language)
        for expectation in expectations {
            let actual = capture(
                of: expectation.word,
                occurrence: expectation.occurrence,
                in: source,
                highlights: found
            )
            let message = "\(language.id): `\(expectation.word)` #\(expectation.occurrence) "
                + "is \(String(describing: actual))"
            if expectation.negated {
                XCTAssertNotEqual(actual, expectation.capture, message)
            } else {
                XCTAssertEqual(actual, expectation.capture, message)
            }
        }
    }

    @MainActor
    func test_c() {
        check("""
        int total = 0;
        void f(int n) {
            total = n + 1;
            total += n;
            count++;
            p->len = n;
        }
        """, language: .c, [
            .init("total", 0, is: .assignedVariable),
            .init("total", 1, is: .assignedVariable),
            .init("total", 2, is: .assignedVariable),
            .init("n", 0, is: .parameter),
            .init("n", 1, is: .variable),
            .init("count", is: .assignedVariable),
            .init("p", is: .variable),
            .init("len", is: .property),
            .init("f", is: .function)
        ])
    }

    @MainActor
    func test_cpp() {
        check("""
        int main() {
            int total = 0;
            int other;
            total = other + 1;
            return total;
        }
        """, language: .cpp, [
            .init("total", 0, is: .assignedVariable),
            .init("total", 1, is: .assignedVariable),
            .init("total", 2, is: .variable),
            .init("other", 0, is: .variable),
            .init("other", 1, is: .variable),
            .init("main", is: .function)
        ])
    }

    @MainActor
    func test_swift() {
        check("""
        var total = 0
        let name = "x"
        var empty: Int
        func f(n: Int) {
            total = n + 1
            self.total = n
        }
        """, language: .swift, [
            .init("total", 0, is: .assignedVariable),
            .init("name", is: .assignedVariable),
            .init("empty", is: .variable),
            .init("total", 1, is: .assignedVariable),
            .init("total", 2, is: .assignedVariable),
            .init("n", 0, is: .parameter)
        ])
    }

    @MainActor
    func test_python() {
        check("""
        total = 0
        MAX = 10
        def f(n):
            total = n + 1
            obj.count += 1
            for i in items:
                pass
        """, language: .python, [
            .init("total", 0, is: .assignedVariable),
            .init("MAX", is: .constant),
            .init("total", 1, is: .assignedVariable),
            .init("n", 1, is: .variable),
            .init("obj", is: .variable),
            .init("count", is: .assignedVariable),
            .init("i", is: .assignedVariable),
            .init("items", is: .variable)
        ])
    }

    @MainActor
    func test_cmake() {
        check("""
        set(MY_VAR 1)
        set(my_var ${OTHER} PARENT_SCOPE)
        list(APPEND my_list x)
        foreach(item IN LISTS my_list)
        endforeach()
        project(Demo)
        """, language: .cmake, [
            .init("MY_VAR", is: .assignedVariable),
            .init("my_var", is: .assignedVariable),
            .init("OTHER", is: .variable),
            .init("my_list", 0, is: .assignedVariable),
            .init("item", is: .assignedVariable),
            .init("PARENT_SCOPE", is: .constant),
            .init("Demo", is: nil),
            .init("project", is: .function)
        ])
    }
}

extension AssignedVariableQueryTests {
    @MainActor
    func test_javascript() {
        check("""
        let total = 0;
        const f = () => {};
        function g(n) {
            total = n + 1;
            obj.count += 1;
            n++;
        }
        """, language: .javascript, [
            .init("total", 0, is: .assignedVariable),
            .init("f", is: .function),
            .init("g", is: .function),
            .init("total", 1, is: .assignedVariable),
            .init("count", is: .assignedVariable),
            .init("n", 2, is: .assignedVariable)
        ])
    }

    @MainActor
    func test_go() {
        check("""
        package main
        func main() {
            x := 1
            var y = 2
            var z int
            x = y + z
            x++
        }
        """, language: .go, [
            .init("x", 0, is: .assignedVariable),
            .init("y", 0, is: .assignedVariable),
            .init("z", 0, is: .variable),
            .init("x", 1, is: .assignedVariable),
            .init("y", 1, is: .variable),
            .init("x", 2, is: .assignedVariable)
        ])
    }

    @MainActor
    func test_rust() {
        check("""
        fn main() {
            let mut x = 1;
            let y = 2;
            x = y + 1;
            x += 1;
        }
        """, language: .rust, [
            .init("x", 0, is: .assignedVariable),
            .init("y", 0, is: .assignedVariable),
            .init("x", 1, is: .assignedVariable),
            .init("x", 2, is: .assignedVariable)
        ])
        check("fn main() { let y = 2; let z = y; }", language: .rust, [
            .init("y", 1, isNot: .assignedVariable),
            .init("z", is: .assignedVariable)
        ])
    }

    @MainActor
    func test_java() {
        check("""
        class A {
            void f(int n) {
                int total = n;
                total = n + 1;
                total++;
            }
        }
        """, language: .java, [
            .init("total", 0, is: .assignedVariable),
            .init("total", 1, is: .assignedVariable),
            .init("total", 2, is: .assignedVariable),
            .init("n", 1, is: .variable)
        ])
    }

    @MainActor
    func test_kotlin() {
        check("""
        val x = 1
        var y: Int
        fun f() {
            y = x + 1
        }
        """, language: .kotlin, [
            .init("x", 0, is: .assignedVariable),
            .init("y", 0, is: .variable),
            .init("y", 1, is: .assignedVariable),
            .init("x", 1, is: .variable)
        ])
    }

    @MainActor
    func test_bash() {
        check("""
        FOO=bar
        echo $FOO
        for f in a b; do echo $f; done
        """, language: .bash, [
            .init("FOO", 0, is: .assignedVariable),
            .init("FOO", 1, is: .property),
            .init("f", 0, is: .assignedVariable)
        ])
    }

    @MainActor
    func test_lua() {
        check("""
        local total = 0
        total = total + 1
        obj.count = 2
        for i = 1, 10 do end
        """, language: .lua, [
            .init("total", 0, is: .assignedVariable),
            .init("total", 1, is: .assignedVariable),
            .init("total", 2, is: .variable),
            .init("count", is: .assignedVariable),
            .init("i", is: .assignedVariable)
        ])
    }

    @MainActor
    func test_ruby() {
        check("""
        total = 0
        total += n
        @count = 1
        """, language: .ruby, [
            .init("total", 0, is: .assignedVariable),
            .init("total", 1, is: .assignedVariable),
            .init("@count", is: .assignedVariable),
            .init("n", isNot: .assignedVariable)
        ])
    }
}
