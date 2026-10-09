//
//  GoldenMemberAndScopeCases.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation
@testable import CodeEdit

/// Golden cases for completing after `.`, `->` and `::`.
enum GoldenMemberAndScopeCases {
    private static let inBody = ["compound_statement", "function_definition", "translation_unit"]

    static let all: [GoldenCase] = [
        GoldenCase(
            name: "member access offers members, never snippets or keywords",
            line: "    point.",
            nodeTypes: ["field_expression"] + inBody,
            expectedIntent: .memberAccess,
            items: [
                .lsp("x", .variable), .lsp("y", .variable), .lsp("length", .function),
                .snippet("for"), .keyword("return")
            ],
            expectedTop: ["x", "y", "length"]
        ),
        GoldenCase(
            name: "member access: the exactly typed member is preselected",
            line: "    point.len",
            nodeTypes: ["field_expression"] + inBody,
            expectedIntent: .memberAccess,
            items: [.lsp("length", .function), .lsp("clear", .function), .lsp("x", .variable)],
            expectedTop: ["length"],
            expectedPreselection: .label("length")
        ),
        GoldenCase(
            name: "member access prefers a frequently accepted method in this intent",
            line: "    list.",
            nodeTypes: ["field_expression"] + inBody,
            expectedIntent: .memberAccess,
            items: [.lsp("begin", .function), .lsp("clear", .function), .lsp("push_back", .function)],
            expectedTop: ["push_back", "begin", "clear"],
            intentFrequencies: ["push_back": 40]
        ),
        GoldenCase(
            name: "scope access keeps namespaces and types ahead of values",
            line: "    std::",
            nodeTypes: inBody,
            expectedIntent: .scopeAccess,
            items: [
                .lsp("string", .class), .lsp("chrono", .namespace), .lsp("move", .function),
                .lsp("npos", .variable), .keyword("namespace")
            ],
            expectedTop: ["string", "chrono", "move"]
        ),
        GoldenCase(
            name: "scope access: a unique typed match is preselected",
            line: "    std::vec",
            nodeTypes: inBody,
            expectedIntent: .scopeAccess,
            items: [.lsp("vector", .class), .lsp("variant", .class), .lsp("visit", .function)],
            expectedTop: ["vector"],
            expectedPreselection: .label("vector")
        )
    ]
}
