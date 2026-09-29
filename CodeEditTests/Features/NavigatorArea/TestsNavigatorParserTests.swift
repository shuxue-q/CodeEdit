//
//  TestsNavigatorParserTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 9/22/26.
//

import XCTest
@testable import CodeEdit

final class TestsNavigatorParserTests: XCTestCase {
    func testXCTestSuiteAndCaseWithExactLineNumbers() {
        let source = """
        import XCTest

        final class FooTests: XCTestCase {
            func testBar() {}
        }
        """
        let suites = TestsNavigatorParser.parse(source: source)
        XCTAssertEqual(suites.count, 1)
        XCTAssertEqual(suites[0].name, "FooTests")
        XCTAssertEqual(suites[0].line, 3)
        XCTAssertEqual(suites[0].tests.count, 1)
        XCTAssertEqual(suites[0].tests[0].name, "testBar")
        XCTAssertEqual(suites[0].tests[0].line, 4)
    }

    func testSubclassWithTestCaseInSuperclassNameIsDetected() {
        let source = """
        class FooTests: BaseTestCase {
            func testSomething() {}
        }
        """
        let suites = TestsNavigatorParser.parse(source: source)
        XCTAssertEqual(suites.map(\.name), ["FooTests"])
        XCTAssertEqual(suites[0].tests.map(\.name), ["testSomething"])
    }

    func testClassEndingInTestsWithNonTestCaseSuperclassIsDetected() {
        let source = """
        class WidgetTests: NSObject {
            func testRenders() {}
        }
        """
        let suites = TestsNavigatorParser.parse(source: source)
        XCTAssertEqual(suites.map(\.name), ["WidgetTests"])
        XCTAssertEqual(suites[0].tests.map(\.name), ["testRenders"])
    }

    func testClassWithoutTestCaseSuperclassOrTestsSuffixIsNotDetected() {
        let source = """
        class Helper: NSObject {
            func testNotInASuite() {}
        }
        """
        XCTAssertTrue(TestsNavigatorParser.parse(source: source).isEmpty)
    }

    func testUnderscoreAndAsyncThrowingTestMethodsAreDetected() {
        let source = """
        final class SignatureTests: XCTestCase {
            func test_underscore() {}
            func testAsync() async throws {}
            func setUp() {}
            func helper() {}
        }
        """
        let suites = TestsNavigatorParser.parse(source: source)
        XCTAssertEqual(suites.count, 1)
        XCTAssertEqual(suites[0].tests.map(\.name), ["test_underscore", "testAsync"])
        XCTAssertEqual(suites[0].tests.map(\.line), [2, 3])
    }

    func testSwiftTestingSuiteOnSingleLine() {
        let source = "@Suite struct FooSuite { @Test func bar() {} }"
        let suites = TestsNavigatorParser.parse(source: source)
        XCTAssertEqual(suites.count, 1)
        XCTAssertEqual(suites[0].name, "FooSuite")
        XCTAssertEqual(suites[0].line, 1)
        XCTAssertEqual(suites[0].tests.map(\.name), ["bar"])
        XCTAssertEqual(suites[0].tests.map(\.line), [1])
    }

    func testSwiftTestingAttributesWithArguments() {
        let source = """
        @Suite
        struct TaggedSuite {
            @Test("display name")
            func baz() {}
            @Test(arguments: [1, 2])
            func qux(_ value: Int) {}
        }
        """
        let suites = TestsNavigatorParser.parse(source: source)
        XCTAssertEqual(suites.count, 1)
        XCTAssertEqual(suites[0].name, "TaggedSuite")
        XCTAssertEqual(suites[0].line, 2)
        XCTAssertEqual(suites[0].tests.map(\.name), ["baz", "qux"])
        XCTAssertEqual(suites[0].tests.map(\.line), [4, 6])
    }

    func testTestAttributeSeparatedByOtherAttributes() {
        let source = """
        @Suite
        struct AttrSuite {
            @Test
            @MainActor
            func something() {}
        }
        """
        let suites = TestsNavigatorParser.parse(source: source)
        XCTAssertEqual(suites.count, 1)
        XCTAssertEqual(suites[0].name, "AttrSuite")
        XCTAssertEqual(suites[0].tests.map(\.name), ["something"])
        XCTAssertEqual(suites[0].tests.map(\.line), [5])
    }

    func testCommentedOutDeclarationsAreIgnored() {
        let source = """
        // class FakeTests: XCTestCase {
        //     func testFake() {}
        // }
        final class RealTests: XCTestCase {
            func testReal() {}
        }
        """
        let suites = TestsNavigatorParser.parse(source: source)
        XCTAssertEqual(suites.map(\.name), ["RealTests"])
        XCTAssertEqual(suites[0].line, 4)
        XCTAssertEqual(suites[0].tests.map(\.name), ["testReal"])
        XCTAssertEqual(suites[0].tests.map(\.line), [5])
    }

    func testSuiteAndTestDeclaredOnTheSameLine() {
        let source = "class SingleLineTests: XCTestCase { func testA() {} }"
        let suites = TestsNavigatorParser.parse(source: source)
        XCTAssertEqual(suites.count, 1)
        XCTAssertEqual(suites[0].name, "SingleLineTests")
        XCTAssertEqual(suites[0].line, 1)
        XCTAssertEqual(suites[0].tests.map(\.name), ["testA"])
        XCTAssertEqual(suites[0].tests.map(\.line), [1])
    }

    func testMethodsAfterSuiteClosingBraceAreNotAttributed() {
        let source = """
        class BraceTests: XCTestCase {
            func testInside() {}
        }

        func testOutside() {}
        """
        let suites = TestsNavigatorParser.parse(source: source)
        XCTAssertEqual(suites.count, 1)
        XCTAssertEqual(suites[0].tests.map(\.name), ["testInside"])
    }

    func testTrailingCommentDoesNotBreakSuiteDetection() {
        let source = """
        final class TrailingTests: XCTestCase { // the suite
            func testTrailing() {} // the test
        }
        """
        let suites = TestsNavigatorParser.parse(source: source)
        XCTAssertEqual(suites.map(\.name), ["TrailingTests"])
        XCTAssertEqual(suites[0].tests.map(\.name), ["testTrailing"])
    }

    func testEmptySourceYieldsNoSuites() {
        XCTAssertTrue(TestsNavigatorParser.parse(source: "").isEmpty)
    }
}
