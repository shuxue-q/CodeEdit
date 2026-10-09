//
//  GoldenSemanticCases.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation
@testable import CodeEdit

/// Golden cases for the signals that know what the slot expects: the declared type of an initializer, the
/// return type, the parameter of a call, the type of a `switch` condition, and postfix templates.
enum GoldenSemanticCases {
    private static let inBody = ["compound_statement", "function_definition", "translation_unit"]

    static let all: [GoldenCase] = [
        GoldenCase(
            name: "initializer of a declared std::string lifts the string, then the convertible numbers",
            line: "    std::string s = ",
            nodeTypes: ["init_declarator", "declaration"] + inBody,
            expectedIntent: .expression,
            items: [
                .lsp("count", .variable, detail: "int"),
                .lsp("label", .variable, detail: "const std::string &"),
                .lsp("title", .function, detail: "basic_string<char>"),
                .lsp("Config", .class)
            ],
            expectedTop: ["label", "title", "count"],
            slotTypes: GoldenCase.SlotTypes()
        ),
        GoldenCase(
            name: "initializer of a double prefers doubles, then other numbers, over unrelated types",
            line: "    double ratio = ",
            nodeTypes: ["init_declarator", "declaration"] + inBody,
            expectedIntent: .expression,
            items: [
                .lsp("name", .variable, detail: "std::string"),
                .lsp("count", .variable, detail: "int"),
                .lsp("scale", .variable, detail: "double")
            ],
            expectedTop: ["scale", "count", "name"],
            slotTypes: GoldenCase.SlotTypes()
        ),
        GoldenCase(
            name: "return in a function returning Color lifts values of that type",
            line: "    return ",
            nodeTypes: ["return_statement"] + inBody,
            expectedIntent: .expression,
            items: [
                .lsp("count", .variable, detail: "int"),
                .lsp("toColor", .function, detail: "Color"),
                .lsp("color", .variable, detail: "Color"),
                .lsp("Palette", .class)
            ],
            expectedTop: ["toColor", "color", "count"],
            expectedType: "Color"
        ),
        GoldenCase(
            name: "return while the syntax tree has no function reads the return type from the text",
            line: "    return ",
            nodeTypes: ["translation_unit"],
            expectedIntent: .expression,
            items: [
                .lsp("count", .variable, detail: "int"),
                .lsp("toColor", .function, detail: "Color"),
                .lsp("color", .variable, detail: "Color"),
                .lsp("Palette", .class)
            ],
            expectedTop: ["toColor", "color", "count"],
            precedingText: "Color paint(int n) {\n",
            slotTypes: GoldenCase.SlotTypes()
        ),
        GoldenCase(
            name: "call argument takes the type of the parameter from signature help",
            line: "    draw(p",
            nodeTypes: ["argument_list", "call_expression"] + inBody,
            expectedIntent: .expression,
            items: [
                .lsp("pad", .variable, detail: "int"),
                .lsp("pos", .variable, detail: "Point"),
                .lsp("px", .variable, detail: "int"),
                .lsp("pt", .variable, detail: "Point *")
            ],
            expectedTop: ["pos"],
            slotTypes: GoldenCase.SlotTypes(parameter: "const Point &origin")
        ),
        GoldenCase(
            name: "case label takes the type of the switch condition from hover",
            line: "    case R",
            nodeTypes: ["case_statement", "switch_statement"] + inBody,
            expectedIntent: .caseLabel,
            items: [
                .lsp("RED", .enumMember, detail: "Color"),
                .lsp("RETRY", .macro),
                .lsp("RUN", .enumMember, detail: "Mode"),
                .lsp("Rect", .class)
            ],
            expectedTop: ["RUN"],
            precedingText: "    switch (mode) {\n",
            slotTypes: GoldenCase.SlotTypes(symbols: ["mode": "Mode"])
        ),
        GoldenCase(
            name: "a postfix template typed in full outranks members that merely match",
            line: "    v.for",
            nodeTypes: ["field_expression"] + inBody,
            expectedIntent: .memberAccess,
            items: [
                .lsp("format", .function), .lsp("forward", .function), .lsp("front", .function),
                .postfix("for"), .postfix("fori")
            ],
            expectedTop: ["for"]
        ),
        GoldenCase(
            name: "a partly typed postfix template stays below the matching members",
            line: "    v.fo",
            nodeTypes: ["field_expression"] + inBody,
            expectedIntent: .memberAccess,
            items: [
                .lsp("format", .function), .lsp("forward", .function), .postfix("for"), .postfix("fori")
            ],
            expectedTop: ["format", "forward"]
        ),
        GoldenCase(
            name: "postfix templates are not offered after a dot outside member access",
            line: "    x = if",
            nodeTypes: ["assignment_expression"] + inBody,
            expectedIntent: .expression,
            items: [.lsp("iffy", .variable), .postfix("if")],
            expectedTop: ["iffy"],
            expectedPreselection: .label("iffy")
        )
    ]
}
