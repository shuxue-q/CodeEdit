//
//  TOMLDocumentTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation
import Testing
@testable import CodeEdit

@Suite
struct TOMLDocumentTests {
    @Test
    func readsScalarsTablesAndComments() {
        let document = TOMLDocument.parse("""
        # comment
        title = "TOML" # trailing
        count = 1_000
        hex = 0xff
        ratio = 1.5e3
        enabled = true
        date = 1979-05-27 07:32:00

        [package]
        name = 'literal\\path'
        "quoted key" = "a#b"
        """)
        #expect(document.errors.isEmpty)
        #expect(document.value(at: "title")?.string == "TOML")
        #expect(document.value(at: "count")?.integer == 1000)
        #expect(document.value(at: "hex")?.integer == 255)
        #expect(document.value(at: "ratio") == .float(1500))
        #expect(document.value(at: "enabled")?.boolean == true)
        #expect(document.value(at: "date") == .dateTime("1979-05-27 07:32:00"))
        #expect(document.value(at: "package", "name")?.string == "literal\\path")
        #expect(document.value(at: "package", "quoted key")?.string == "a#b")
    }

    @Test
    func readsArraysInlineTablesAndDottedKeys() {
        let document = TOMLDocument.parse("""
        members = [
            "crates/a", # first
            "crates/b",
        ]
        nested = [[1, 2], ["x"]]
        serde = { version = "1", features = ["derive"], optional = true }
        site.url = "https://example.com"
        """)
        #expect(document.errors.isEmpty)
        #expect(document.value(at: "members")?.strings == ["crates/a", "crates/b"])
        #expect(document.value(at: "nested")?.array?.count == 2)
        #expect(document.value(at: "serde", "features")?.strings == ["derive"])
        #expect(document.value(at: "serde", "optional")?.boolean == true)
        #expect(document.value(at: "site", "url")?.string == "https://example.com")
    }

    @Test
    func readsArraysOfTablesAndSubtables() {
        let document = TOMLDocument.parse("""
        [[bin]]
        name = "first"

        [[bin]]
        name = "second"
        path = "src/second.rs"

        [bin.metadata]
        note = "belongs to the second bin"
        """)
        #expect(document.errors.isEmpty)
        let bins = document.value(at: "bin")?.array ?? []
        #expect(bins.count == 2)
        #expect(bins.last?["name"]?.string == "second")
        #expect(bins.last?["metadata"]?["note"]?.string == "belongs to the second bin")
    }

    @Test
    func readsMultilineAndEscapedStrings() {
        let document = TOMLDocument.parse(#"""
        basic = """
        line one
        line two \
            continued"""
        literal = '''
        C:\raw\path'''
        escaped = "tab\tquote\"unicode\u00E9"
        """#)
        #expect(document.errors.isEmpty)
        #expect(document.value(at: "basic")?.string == "line one\nline two continued")
        #expect(document.value(at: "literal")?.string == #"C:\raw\path"#)
        #expect(document.value(at: "escaped")?.string == "tab\tquote\"unicodeé")
    }

    @Test
    func keepsKeyOrder() {
        let document = TOMLDocument.parse("""
        [features]
        default = ["std"]
        std = []
        alloc = []
        """)
        #expect(document.value(at: "features")?.table?.keys == ["default", "std", "alloc"])
    }

    @Test
    func reportsBadLinesAndKeepsTheRest() {
        let document = TOMLDocument.parse("""
        good = 1
        bad =
        broken = "unterminated
        dup = 1
        dup = 2
        after = "still read"
        """)
        #expect(document.errors.map(\.line) == [2, 3, 5])
        #expect(document.value(at: "good")?.integer == 1)
        #expect(document.value(at: "dup")?.integer == 1)
        #expect(document.value(at: "after")?.string == "still read")
    }
}
