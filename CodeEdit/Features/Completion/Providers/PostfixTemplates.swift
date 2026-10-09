//
//  PostfixTemplates.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// The postfix templates for C and C++: `expr.if`, `expr.fori`, `expr.var`, …
///
/// Each template turns the expression before the `.` into a statement or a larger expression. The
/// expansion is written in LSP snippet syntax: `$0` is the final caret, `${1:name}` a tab stop, and a
/// repeated `$2` a mirror of the second stop.
enum PostfixTemplates {
    /// The expression a template is applied to, and what is known about it.
    struct Expression: Equatable {
        /// The expression as written, for example `items` or `values[i]`.
        var text: String
        /// Whether the syntax tree says the expression names a type (`Widget`, `std::string`).
        var isTypeName = false

        /// A lone name, a member chain, or a call: an expression that needs no parentheses after `!`.
        var isAtomic: Bool {
            text.range(
                of: #"^[A-Za-z_]\w*(?:(?:\.|->|::)[A-Za-z_]\w*)*(?:\(.*\))?$"#,
                options: .regularExpression
            ) != nil
        }

        /// `text` as it may appear inside a snippet body, where `$`, `}` and `\` are special.
        var escaped: String {
            var result = ""
            for character in text {
                if "\\$}".contains(character) { result.append("\\") }
                result.append(character)
            }
            return result
        }
    }

    /// One template.
    struct Template {
        /// What the user types after the `.`.
        let label: String
        /// The row's detail; `%@` stands for the expression.
        let detail: String
        /// Whether the template only exists in C++.
        let cppOnly: Bool
        /// Extra condition on the expression, besides the language.
        let accepts: (Expression) -> Bool
        /// The snippet that replaces `expr.label`, for C++ (`true`) or C (`false`).
        let body: (_ expression: Expression, _ isCpp: Bool) -> String

        init(
            label: String,
            detail: String,
            cppOnly: Bool = false,
            accepts: @escaping (Expression) -> Bool = { _ in true },
            body: @escaping (_ expression: Expression, _ isCpp: Bool) -> String
        ) {
            self.label = label
            self.detail = detail
            self.cppOnly = cppOnly
            self.accepts = accepts
            self.body = body
        }
    }

    /// Whether `languageId` is C++ (as opposed to C) among the C-family languages.
    static func isCpp(_ languageId: String) -> Bool {
        CFamilyKeywords.languageIds.contains(languageId) && !CFamilyKeywords.cLanguageIds.contains(languageId)
    }

    /// The templates that apply to `expression` in `languageId`, in table order.
    static func templates(for expression: Expression, languageId: String) -> [Template] {
        guard CFamilyKeywords.languageIds.contains(languageId) else { return [] }
        let isCpp = isCpp(languageId)
        return all.filter { (isCpp || !$0.cppOnly) && $0.accepts(expression) }
    }

    /// The snippet `template` expands `expression` to.
    static func expansion(of template: Template, for expression: Expression, languageId: String) -> String {
        template.body(expression, isCpp(languageId))
    }

    /// The row detail of `template` for `expression`: its expansion in short form.
    static func detail(of template: Template, for expression: Expression) -> String {
        let shown = expression.text.count > 24 ? String(expression.text.prefix(23)) + "…" : expression.text
        return template.detail.replacingOccurrences(of: "%@", with: shown)
    }

    /// Whether `text` looks like a type: a qualified name whose last part is capitalized, a `std::` name,
    /// or a primitive. A fallback for when the syntax tree does not classify the expression.
    static func looksLikeTypeName(_ text: String) -> Bool {
        guard text.range(of: #"^[A-Za-z_][\w:]*(?:<.*>)?$"#, options: .regularExpression) != nil else {
            return false
        }
        let name = text.split(separator: "<", maxSplits: 1).first.map(String.init) ?? text
        let last = name.components(separatedBy: "::").last ?? name
        let primitives: Set<String> = ["int", "char", "bool", "float", "double", "long", "short", "unsigned"]
        return last.first?.isUppercase == true || name.hasPrefix("std::") || primitives.contains(name)
    }

    // MARK: - Table

    static let all: [Template] = [
        Template(label: "if", detail: "if (%@) {…}") { expr, _ in
            "if (\(expr.escaped)) {\n\t$0\n}"
        },
        Template(label: "else", detail: "if (!(%@)) {…}") { expr, _ in
            "if (!(\(expr.escaped))) {\n\t$0\n}"
        },
        Template(label: "not", detail: "!%@") { expr, _ in
            expr.isAtomic ? "!\(expr.escaped)$0" : "!(\(expr.escaped))$0"
        },
        Template(label: "while", detail: "while (%@) {…}") { expr, _ in
            "while (\(expr.escaped)) {\n\t$0\n}"
        },
        Template(label: "for", detail: "for (const auto &item : %@) {…}", cppOnly: true) { expr, _ in
            "for (const auto &${1:item} : \(expr.escaped)) {\n\t$0\n}"
        },
        Template(label: "fori", detail: "for (size_t i = 0; i < %@; ++i) {…}") { expr, _ in
            "for (${1:size_t} ${2:i} = 0; $2 < \(expr.escaped); ++$2) {\n\t$0\n}"
        },
        Template(label: "forr", detail: "for (size_t i = %@ - 1; i >= 0; --i) {…}") { expr, _ in
            "for (${1:size_t} ${2:i} = \(expr.escaped) - 1; $2 >= 0; --$2) {\n\t$0\n}"
        },
        Template(label: "return", detail: "return %@;") { expr, _ in
            "return \(expr.escaped);$0"
        },
        Template(label: "var", detail: "auto name = %@;") { expr, isCpp in
            isCpp ? "auto ${1:name} = \(expr.escaped);$0" : "${1:int} ${2:name} = \(expr.escaped);$0"
        },
        Template(
            label: "new",
            detail: "new %@()",
            cppOnly: true,
            accepts: { $0.isTypeName },
            body: { expr, _ in "new \(expr.escaped)($0)" }
        ),
        Template(label: "par", detail: "(%@)") { expr, _ in
            "(\(expr.escaped))$0"
        },
        Template(label: "cast", detail: "static_cast<T>(%@)") { expr, isCpp in
            isCpp ? "static_cast<${1:T}>(\(expr.escaped))$0" : "(${1:T})\(expr.escaped)$0"
        },
        Template(label: "switch", detail: "switch (%@) {…}") { expr, _ in
            "switch (\(expr.escaped)) {\n\tcase $1:\n\t\t$0\n}"
        },
        Template(label: "nn", detail: "if (%@ != nullptr) {…}") { expr, isCpp in
            "if (\(expr.escaped) != \(isCpp ? "nullptr" : "NULL")) {\n\t$0\n}"
        }
    ]
}
