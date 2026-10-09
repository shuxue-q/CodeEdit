//
//  TypeTextTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest
@testable import CodeEdit

final class TypeTextTests: XCTestCase {
    private func parse(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> TypeText {
        try XCTUnwrap(TypeText.parse(text), "`\(text)` did not parse", file: file, line: line)
    }

    // MARK: - Normalization

    func testQualifiersAndReferencesAreDropped() throws {
        XCTAssertEqual(try parse("const std::string &"), TypeText(name: "std::string"))
        XCTAssertEqual(try parse("volatile int &&"), TypeText(name: "int"))
        XCTAssertEqual(try parse("struct Point"), TypeText(name: "Point"))
    }

    func testPointersAreCountedNotKept() throws {
        XCTAssertEqual(try parse("const char *"), TypeText(name: "char", pointerDepth: 1))
        XCTAssertEqual(try parse("char **"), TypeText(name: "char", pointerDepth: 2))
        XCTAssertEqual(try parse("int * const"), TypeText(name: "int", pointerDepth: 1))
        XCTAssertEqual(try parse("char **").description, "char**")
    }

    func testLeadingScopeAndInlineNamespacesAreCollapsed() throws {
        XCTAssertEqual(try parse("::Foo"), TypeText(name: "Foo"))
        XCTAssertEqual(try parse("std::__1::vector<int>"), TypeText(name: "std::vector<int>"))
        XCTAssertEqual(try parse("std::__cxx11::list<int>"), TypeText(name: "std::list<int>"))
    }

    func testTemplateArgumentsAreKeptWithoutWhitespaceNoise() throws {
        XCTAssertEqual(try parse("std::map<int, std::string>"), try parse("std::map<int,std::string>"))
        XCTAssertEqual(try parse("std::vector<std::pair<int, int> >").name, "std::vector<std::pair<int,int>>")
        XCTAssertEqual(try parse("std::vector<const char *>").name, "std::vector<const char*>")
    }

    func testDifferentTemplateArgumentsAreDifferentTypes() throws {
        XCTAssertNotEqual(try parse("std::vector<int>"), try parse("std::vector<double>"))
    }

    func testSpellingsOfThePrimitivesAreFolded() throws {
        XCTAssertEqual(try parse("unsigned"), try parse("unsigned int"))
        XCTAssertEqual(try parse("long int"), try parse("long"))
        XCTAssertEqual(try parse("long unsigned int"), try parse("unsigned long"))
        XCTAssertEqual(try parse("signed int"), try parse("int"))
        XCTAssertEqual(try parse("long long int"), try parse("long long"))
        XCTAssertEqual(try parse("unsigned char").name, "unsigned char")
        XCTAssertEqual(try parse("long double").name, "long double")
    }

    func testStandardStringSpellingsAreFolded() throws {
        let expected = TypeText(name: "std::string")
        XCTAssertEqual(try parse("std::string"), expected)
        XCTAssertEqual(try parse("basic_string<char>"), expected)
        XCTAssertEqual(try parse("std::basic_string<char>"), expected)
        XCTAssertEqual(
            try parse("std::basic_string<char, std::char_traits<char>, std::allocator<char>>"),
            expected
        )
        XCTAssertEqual(try parse("std::__cxx11::basic_string<char>"), expected)
        XCTAssertEqual(try parse("std::basic_string<wchar_t>").name, "std::basic_string<wchar_t>")
    }

    func testStdQualifiedSizedAliasesMatchTheCLibraryNames() throws {
        XCTAssertEqual(try parse("std::size_t"), try parse("size_t"))
        XCTAssertEqual(try parse("std::uint8_t"), try parse("uint8_t"))
        XCTAssertEqual(try parse("std::vector<int>").name, "std::vector<int>", "Other std names keep std::")
    }

    func testUnknownTypesDoNotParse() {
        XCTAssertNil(TypeText.parse(""))
        XCTAssertNil(TypeText.parse("   "))
        XCTAssertNil(TypeText.parse("auto"))
        XCTAssertNil(TypeText.parse("const auto &"))
        XCTAssertNil(TypeText.parse("decltype(x)"))
    }

    // MARK: - Matching

    func testSameTypeIsAnExactMatch() throws {
        XCTAssertEqual(try parse("std::string").match(try parse("const std::string &")), .exact)
        XCTAssertEqual(try parse("int").match(try parse("signed")), .exact)
        XCTAssertEqual(try parse("char *").match(try parse("const char*")), .exact)
    }

    func testPointerDepthMustAgreeForAnExactMatch() throws {
        XCTAssertEqual(try parse("char *").match(try parse("char")), .none)
        XCTAssertEqual(try parse("Foo *").match(try parse("Foo **")), .none)
    }

    func testNumericTypesConvertAmongThemselves() throws {
        XCTAssertEqual(try parse("double").match(try parse("int")), .convertible)
        XCTAssertEqual(try parse("size_t").match(try parse("long")), .convertible)
        XCTAssertEqual(try parse("float").match(try parse("double")), .convertible)
        XCTAssertEqual(try parse("int").match(try parse("char")), .convertible)
        XCTAssertEqual(try parse("int").match(try parse("bool")), .convertible)
    }

    func testAnEnumeratorConvertsToANumberButANumberDoesNotConvertToAnEnum() throws {
        let number = try parse("int")
        let color = try parse("Color")
        XCTAssertEqual(number.match(color, candidateIsEnumerator: true), .convertible)
        XCTAssertEqual(number.match(color, candidateIsEnumerator: false), .none)
        XCTAssertEqual(color.match(number), .none)
        XCTAssertEqual(color.match(color, candidateIsEnumerator: true), .exact)
    }

    func testAPointerConvertsToBool() throws {
        XCTAssertEqual(try parse("bool").match(try parse("Foo *")), .convertible)
        XCTAssertEqual(try parse("bool").match(try parse("Foo")), .none)
    }

    func testNullptrConvertsToAnyPointer() throws {
        XCTAssertEqual(try parse("Foo *").match(try parse("std::nullptr_t")), .convertible)
        XCTAssertEqual(try parse("Foo").match(try parse("std::nullptr_t")), .none)
    }

    func testAnyPointerConvertsToVoidPointer() throws {
        XCTAssertEqual(try parse("void *").match(try parse("Foo *")), .convertible)
        XCTAssertEqual(try parse("void").match(try parse("Foo")), .none)
    }

    func testUnrelatedTypesDoNotMatch() throws {
        XCTAssertEqual(try parse("std::string").match(try parse("int")), .none)
        XCTAssertEqual(try parse("Foo").match(try parse("Bar")), .none)
        XCTAssertEqual(try parse("int").match(try parse("std::string")), .none)
        XCTAssertEqual(try parse("int").match(try parse("char *")), .none)
    }
}
