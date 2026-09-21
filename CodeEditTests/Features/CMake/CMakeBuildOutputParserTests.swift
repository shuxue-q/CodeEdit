//
//  CMakeBuildOutputParserTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 9/14/26.
//

import XCTest
@testable import CodeEdit

final class CMakeBuildOutputParserTests: XCTestCase {
    private var parser = CMakeBuildOutputParser()

    override func setUp() {
        parser = CMakeBuildOutputParser()
    }

    func testClangDiagnosticWithColumnAndCode() throws {
        parser.feed("/src/main.cpp:12:34: warning: unused variable 'x' [-Wunused-variable]\n")
        let diagnostic = try XCTUnwrap(parser.currentDiagnostics.first)
        XCTAssertEqual(diagnostic.severity, .warning)
        XCTAssertEqual(diagnostic.filePath, "/src/main.cpp")
        XCTAssertEqual(diagnostic.line, 12)
        XCTAssertEqual(diagnostic.column, 34)
        XCTAssertEqual(diagnostic.message, "unused variable 'x'")
        XCTAssertEqual(diagnostic.code, "-Wunused-variable")
    }

    func testGccDiagnosticWithoutColumn() throws {
        parser.feed("main.c:8: error: expected ';' before 'return'\n")
        let diagnostic = try XCTUnwrap(parser.currentDiagnostics.first)
        XCTAssertEqual(diagnostic.severity, .error)
        XCTAssertEqual(diagnostic.filePath, "main.c")
        XCTAssertEqual(diagnostic.line, 8)
        XCTAssertNil(diagnostic.column)
        XCTAssertEqual(diagnostic.message, "expected ';' before 'return'")
    }

    func testFatalErrorAndNoteAttachment() throws {
        parser.feed("""
        /src/pch.h:3:10: fatal error: 'missing.h' file not found
        /src/pch.h:1:2: note: in file included from here
        """)
        parser.finish()
        XCTAssertEqual(parser.currentDiagnostics.count, 1)
        let diagnostic = try XCTUnwrap(parser.currentDiagnostics.first)
        XCTAssertEqual(diagnostic.severity, .error)
        XCTAssertEqual(diagnostic.message, "'missing.h' file not found\nin file included from here")
    }

    func testMsvcDiagnostic() throws {
        parser.feed(#"C:\proj\app.cpp(42,7): warning C4996: 'strcpy' was declared deprecated"# + "\n")
        let diagnostic = try XCTUnwrap(parser.currentDiagnostics.first)
        XCTAssertEqual(diagnostic.severity, .warning)
        XCTAssertEqual(diagnostic.filePath, #"C:\proj\app.cpp"#)
        XCTAssertEqual(diagnostic.line, 42)
        XCTAssertEqual(diagnostic.column, 7)
        XCTAssertEqual(diagnostic.code, "C4996")
        XCTAssertEqual(diagnostic.message, "'strcpy' was declared deprecated")
    }

    func testToolLevelErrorsWithoutLocation() throws {
        parser.feed("clang: error: linker command failed with exit code 1 (use -v to see invocation)\n")
        let diagnostic = try XCTUnwrap(parser.currentDiagnostics.first)
        XCTAssertEqual(diagnostic.severity, .error)
        XCTAssertNil(diagnostic.filePath)
        XCTAssertEqual(diagnostic.message, "linker command failed with exit code 1 (use -v to see invocation)")
    }

    func testCMakeErrorBlockCollectsIndentedDetails() throws {
        parser.feed("""
        CMake Error at cmake/FindFoo.cmake:12 (find_package):
          By not providing "FindFoo.cmake" in CMAKE_MODULE_PATH this project has
          asked CMake to find a package configuration file provided by "Foo".

        -- Configuring incomplete, errors occurred!
        """)
        parser.finish()
        let diagnostic = try XCTUnwrap(parser.currentDiagnostics.first)
        XCTAssertEqual(diagnostic.severity, .error)
        XCTAssertEqual(diagnostic.filePath, "cmake/FindFoo.cmake")
        XCTAssertEqual(diagnostic.line, 12)
        XCTAssertTrue(diagnostic.message.contains("CMAKE_MODULE_PATH"))
        XCTAssertTrue(diagnostic.message.contains("package configuration file"))
        XCTAssertEqual(parser.currentDiagnostics.count, 1)
    }

    func testCMakeDeprecationAndDevWarnings() throws {
        parser.feed("""
        CMake Deprecation Warning at CMakeLists.txt:1 (cmake_minimum_required):
          Compatibility with CMake < 3.5 will be removed.
        CMake Deprecation Warning: Support for old policies will be removed.
        CMake Warning (dev) at main.cmake:4 (message):
        CMake Warning (dev): some inline dev warning
        """)
        parser.finish()
        let diagnostics = parser.currentDiagnostics
        XCTAssertEqual(diagnostics.count, 4)
        XCTAssertTrue(diagnostics.allSatisfy { $0.severity == .warning })
        XCTAssertEqual(diagnostics[0].filePath, "CMakeLists.txt")
        XCTAssertEqual(diagnostics[0].line, 1)
        XCTAssertTrue(diagnostics[0].message.contains("Compatibility with CMake < 3.5"))
        XCTAssertEqual(diagnostics[1].message, "Support for old policies will be removed.")
        XCTAssertEqual(diagnostics[2].filePath, "main.cmake")
        XCTAssertEqual(diagnostics[2].line, 4)
        XCTAssertEqual(diagnostics[3].message, "some inline dev warning")
    }

    func testNinjaFailedAndMakeErrorsBecomeDiagnostics() throws {
        parser.feed("""
        FAILED: CMakeFiles/app.dir/main.cpp.o /usr/bin/clang++ -c main.cpp
        make[2]: *** [CMakeFiles/app.dir/all] Error 2
        make: *** [all] Error 2
        ninja: build stopped: subcommand failed.
        """)
        parser.finish()
        let diagnostics = parser.currentDiagnostics
        XCTAssertEqual(diagnostics.count, 3)
        XCTAssertTrue(diagnostics.allSatisfy { $0.severity == .error })
        XCTAssertTrue(diagnostics[0].message.contains("Build command failed"))
        XCTAssertEqual(diagnostics[2].message, "make: *** [all] Error 2")
    }

    func testProgressAndSnippetLinesAreIgnored() throws {
        parser.feed("""
        [ 12%] Building CXX object CMakeFiles/app.dir/main.cpp.o
        [==========] 2 tests from 1 test suite ran.
             int main() {
                 ^
        /src/main.cpp:1:1: warning: control reaches end of non-void function [-Wreturn-type]
        """)
        parser.finish()
        XCTAssertEqual(parser.currentDiagnostics.count, 1)
        XCTAssertEqual(parser.currentDiagnostics.first?.severity, .warning)
    }

    func testLinesSplitAcrossChunksAreReassembled() throws {
        let first = parser.feed("/src/main.cpp:7:")
        XCTAssertTrue(first.isEmpty)
        let rest = parser.feed("9: error: redefinition of 'main'\n")
        XCTAssertEqual(rest.count, 1)
        let diagnostic = try XCTUnwrap(rest.first)
        XCTAssertEqual(diagnostic.line, 7)
        XCTAssertEqual(diagnostic.column, 9)
    }

    func testCarriageReturnLineEndingsAreHandled() throws {
        parser.feed("/src/main.cpp:5:1: warning: declared here\r\n")
        XCTAssertEqual(parser.currentDiagnostics.count, 1)
        XCTAssertEqual(parser.currentDiagnostics.first?.filePath, "/src/main.cpp")
    }

    func testFinishFlushesTrailingLineWithoutNewline() throws {
        parser.feed("/src/main.cpp:99:1: error: something")
        XCTAssertTrue(parser.currentDiagnostics.isEmpty)
        parser.finish()
        XCTAssertEqual(parser.currentDiagnostics.count, 1)
        XCTAssertEqual(parser.currentDiagnostics.first?.line, 99)
    }

    func testDiagnosticsAreCapped() throws {
        var output = ""
        for index in 0..<(CMakeBuildOutputParser.maximumDiagnostics + 50) {
            output.append("/src/main.cpp:\(index):1: error: failure \(index)\n")
        }
        parser.feed(output)
        XCTAssertEqual(parser.currentDiagnostics.count, CMakeBuildOutputParser.maximumDiagnostics)
        XCTAssertTrue(parser.isTruncated)
    }
}
