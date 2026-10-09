//
//  GoldenPositionCases.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation
@testable import CodeEdit

/// Golden cases for where a type, a case label, a header path, a value or a statement is expected.
enum GoldenPositionCases {
    private static let inBody = ["compound_statement", "function_definition", "translation_unit"]

    static let all: [GoldenCase] = [
        GoldenCase(
            name: "type position ranks types and type keywords above values",
            line: "    const s",
            nodeTypes: inBody,
            expectedIntent: .typeName,
            items: [
                .lsp("size", .variable), .lsp("string", .class), .keyword("short"),
                .lsp("sort", .function), .snippet("switch")
            ],
            expectedTop: ["string", "short", "size"]
        ),
        GoldenCase(
            name: "template argument position offers types ahead of values",
            line: "    std::vector<u",
            nodeTypes: ["template_argument_list"] + inBody,
            expectedIntent: .typeName,
            items: [
                .lsp("uint8_t", .typeAlias), .keyword("unsigned"),
                .lsp("used", .variable), .lsp("unlink", .function)
            ],
            expectedTop: ["uint8_t", "unsigned", "used"]
        ),
        GoldenCase(
            name: "case label keeps enumerators and macros ahead of types and functions",
            line: "        case R",
            nodeTypes: ["case_statement", "switch_statement"] + inBody,
            expectedIntent: .caseLabel,
            items: [.lsp("RED", .enumMember), .lsp("RETRY", .macro), .lsp("Rect", .class), .lsp("run", .function)],
            expectedTop: ["RED", "RETRY", "Rect"]
        ),
        GoldenCase(
            name: "include path offers headers, not symbols",
            line: "#include <vec",
            nodeTypes: ["preproc_include", "translation_unit"],
            expectedIntent: .includePath,
            items: [.lsp("vec3", .variable), .lsp("vector", .file), .lsp("vec.h", .file), .snippet("include")],
            expectedTop: ["vector", "vec.h", "vec3"]
        ),
        GoldenCase(
            name: "plain expression prefers values and learns what the user picks",
            line: "    total = co",
            nodeTypes: ["assignment_expression"] + inBody,
            expectedIntent: .expression,
            items: [.lsp("compute", .function), .lsp("count", .variable), .keyword("const"), .lsp("Config", .class)],
            expectedTop: ["count", "compute", "const"],
            intentFrequencies: ["count": 12]
        ),
        GoldenCase(
            name: "plain expression favors a symbol the file already uses",
            line: "    return re",
            nodeTypes: ["return_statement"] + inBody,
            expectedIntent: .expression,
            items: [.lsp("reserve", .function), .lsp("result", .variable), .lsp("reset", .function)],
            expectedTop: ["result", "reserve", "reset"],
            documentIdentifiers: ["result"]
        ),
        GoldenCase(
            name: "recently accepted item moves up",
            line: "    total = fo",
            nodeTypes: ["assignment_expression"] + inBody,
            expectedIntent: .expression,
            items: [.lsp("foo_a", .variable), .lsp("foo_b", .variable), .lsp("foo_c", .variable)],
            expectedTop: ["foo_b", "foo_a", "foo_c"],
            acceptedSecondsAgo: ["foo_b": 120]
        ),
        GoldenCase(
            name: "statement start keeps the keyword in front",
            line: "    ret",
            nodeTypes: ["compound_statement"] + inBody,
            expectedIntent: .statement,
            items: [.keyword("return"), .lsp("returns", .function), .lsp("retry_count", .variable)],
            expectedTop: ["return", "returns", "retry_count"]
        ),
        GoldenCase(
            name: "without a server, document words fill in at low priority",
            line: "    cou",
            nodeTypes: ["compound_statement"] + inBody,
            expectedIntent: .statement,
            items: [.word("counter"), .word("couple"), .keyword("continue")],
            expectedTop: ["counter", "couple"]
        ),
        GoldenCase(
            name: "a word never competes with the symbol of the same name",
            line: "    total = va",
            nodeTypes: ["assignment_expression"] + inBody,
            expectedIntent: .expression,
            items: [.word("value"), .lsp("value", .variable), .word("variance")],
            expectedTop: ["value", "variance"]
        )
    ]
}
