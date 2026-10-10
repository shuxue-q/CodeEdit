import XCTest
import CodeEditLanguages
import CodeEditTextView
@testable import CodeEditSourceEditor

/// Verifies the symbol roles (members, parameters, primitive types, macros, namespaces, preprocessor directives)
/// that the grammar queries produce on their own, without a language server.
extension AssignedVariableQueryTests {
    /// Without a language server the grammar alone separates members, parameters, primitive types, macros,
    /// namespaces and preprocessor directives from plain variables.
    @MainActor
    func test_cpp_symbolHierarchy() {
        check("""
        #include <cmath>
        #define LIMIT 10
        #define SQUARE(x) ((x) * (x))
        namespace geo {
        struct Dual { double value; double grad; };
        double convert(Dual &p, const double *meters, int mode = 1, char **names) {
            unsigned long count = 0;
            double local = 1.0;
            p.grad = local;
            return local;
        }
        }
        """, language: .cpp, [
            .init("#include", is: .preprocessor),
            .init("#define", 0, is: .preprocessor),
            .init("LIMIT", 0, is: .macro),
            .init("SQUARE", 0, is: .macro),
            .init("geo", is: .namespace),
            .init("value", is: .property),
            .init("grad", 0, is: .property),
            .init("grad", 1, is: .property),
            .init("double", 0, is: .primitiveType),
            .init("int", is: .primitiveType),
            .init("unsigned long", is: .primitiveType),
            .init("convert", is: .function),
            .init("p", 0, is: .parameter),
            .init("meters", is: .parameter),
            .init("mode", is: .parameter),
            .init("names", is: .parameter),
            .init("local", 0, is: .assignedVariable),
            .init("local", 1, is: .variable),
            .init("count", is: .assignedVariable)
        ])
    }

    /// When several patterns capture the same range the client emits one highlight, the most specific one. Providers
    /// keep the first highlight they are given for a range, so a duplicate would let the generic capture win.
    @MainActor
    func test_overlappingCapturesEmitOneHighlightPerRange() {
        let source = """
        #define LIMIT 10
        constexpr double kScale = 2.0;
        double convert(double meters) {
            int total = 0;
            total = meters;
            return LIMIT + total;
        }
        """
        let textView = Mock.textView()
        textView.setText(source)
        let client = Mock.treeSitterClient(forceSync: true)
        client.setUp(textView: textView, codeLanguage: .cpp)
        var found: [HighlightRange] = []
        let documentRange = NSRange(location: 0, length: (source as NSString).length)
        client.queryHighlightsFor(textView: textView, range: documentRange) {
            if case .success(let ranges) = $0 { found = ranges }
        }
        let nonBracket = found.filter { $0.capture?.bracketLevelIndex == nil }
        XCTAssertEqual(Set(nonBracket.map(\.range)).count, nonBracket.count, "duplicate highlight ranges")
        let nsSource = source as NSString
        func firstCapture(of word: String, occurrence: Int = 0) -> CaptureName? {
            nonBracket.filter { nsSource.substring(with: $0.range) == word }[occurrence].capture
        }
        XCTAssertEqual(firstCapture(of: "LIMIT", occurrence: 0), .macro)
        XCTAssertEqual(firstCapture(of: "LIMIT", occurrence: 1), .constant)
        XCTAssertEqual(firstCapture(of: "convert"), .function)
        XCTAssertEqual(firstCapture(of: "meters", occurrence: 0), .parameter)
        XCTAssertEqual(firstCapture(of: "total", occurrence: 0), .assignedVariable)
        XCTAssertEqual(firstCapture(of: "total", occurrence: 1), .assignedVariable)
        XCTAssertEqual(firstCapture(of: "total", occurrence: 2), .variable)
    }

    /// A qualified name keeps the namespace color on its scope and only the last component gets the name's own role.
    @MainActor
    func test_cpp_qualifiedNamesSplitScopeFromName() {
        check("""
        namespace geo { struct Params { int n; }; double convert(double x); }
        std::string name = "wing";
        geo::Params params;
        std::vector<int> values;
        double r = geo::convert(1.0);
        """, language: .cpp, [
            .init("std", 0, is: .namespace),
            .init("string", is: .type),
            .init("geo", 1, is: .namespace),
            .init("Params", 1, is: .type),
            .init("std", 1, is: .namespace),
            .init("vector", is: .type),
            .init("geo", 2, is: .namespace),
            .init("convert", 1, is: .function)
        ])
    }

    @MainActor
    func test_c_parameters() {
        check("""
        int add(int a, int *b, int c[]) {
            return a + *b + c[0];
        }
        """, language: .c, [
            .init("a", 0, is: .parameter),
            .init("b", 0, is: .parameter),
            .init("c", 0, is: .parameter),
            .init("int", 0, is: .primitiveType),
            .init("add", is: .function)
        ])
    }
}
