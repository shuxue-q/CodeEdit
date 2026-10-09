//
//  PostfixCompletionProvider.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import SwiftTreeSitter

/// Offers postfix templates (`items.for`, `ok.if`, `value.var`) after a `.` in C and C++.
///
/// The expression before the `.` is the syntax-tree node that ends right before it. Accepting a template
/// replaces `expression.label` (including whatever of the label was typed) with the template's snippet,
/// so tab stops work like in any other snippet. Only `.` triggers templates: `->` and `::` do not.
@MainActor
final class PostfixCompletionProvider: CompletionProvider {
    let source: CompletionSource = .postfix
    let deadline: Duration = .zero

    /// The expression that ends at a `.`, as a range in the document.
    private let expressionRange: (_ dotOffset: Int) -> NSRange?
    /// Syntax node types around an offset, innermost first.
    private let nodeTypesAt: (Int) -> [String]
    /// Where the expression of each offered candidate starts, keyed by candidate id.
    private var expressionStarts: [String: Int] = [:]

    /// The longest expression a template is offered for.
    private static let maximumExpressionLength = 400

    /// Creates a provider that reads expressions from the syntax tree of `treeSitterClient`.
    init(treeSitterClient: TreeSitterClient) {
        self.expressionRange = { PostfixExpressionFinder.range(endingAt: $0, in: treeSitterClient) }
        self.nodeTypesAt = { CompletionIntentRecognizer.nodeTypes(at: $0, in: treeSitterClient) }
    }

    /// Creates a provider with injected syntax lookups, for tests.
    init(expressionRange: @escaping (Int) -> NSRange?, nodeTypesAt: @escaping (Int) -> [String] = { _ in [] }) {
        self.expressionRange = expressionRange
        self.nodeTypesAt = nodeTypesAt
    }

    // MARK: - CompletionProvider

    func candidates(for context: CompletionContext, textView: TextViewController) async -> [CompletionCandidate] {
        candidates(for: context)
    }

    /// The templates for the expression before the `.` that precedes the typed prefix.
    func candidates(for context: CompletionContext) -> [CompletionCandidate] {
        expressionStarts = [:]
        guard context.intent == .memberAccess, CFamilyKeywords.languageIds.contains(context.languageId) else {
            return []
        }
        let string = context.documentText as NSString
        let dot = context.prefixRange.location - 1
        guard dot > 0, dot < string.length, string.character(at: dot) == 0x2E,
              let range = expressionRange(dot),
              range.length > 0, range.length <= Self.maximumExpressionLength, NSMaxRange(range) == dot else {
            return []
        }
        let text = string.substring(with: range)
        let expression = PostfixTemplates.Expression(
            text: text,
            isTypeName: nodeTypesAt(range.location).first == "type_identifier"
                || PostfixTemplates.looksLikeTypeName(text)
        )
        return PostfixTemplates.templates(for: expression, languageId: context.languageId).map { template in
            let id = "postfix.\(template.label)"
            expressionStarts[id] = range.location
            return CompletionCandidate(
                id: id,
                label: template.label,
                filterText: template.label,
                sortText: template.label,
                kind: .snippet,
                source: .postfix,
                detail: PostfixTemplates.detail(of: template, for: expression),
                payload: .snippet(
                    body: PostfixTemplates.expansion(of: template, for: expression, languageId: context.languageId)
                )
            )
        }
    }

    func apply(_ candidate: CompletionCandidate, textView: TextViewController, cursorPosition: CursorPosition?) {
        guard case .snippet(let body) = candidate.payload,
              let start = expressionStarts[candidate.id],
              let cursorPosition,
              let resolved = textView.resolveCursorPosition(cursorPosition) else {
            return
        }
        let end = resolved.range.location
        guard end >= start else { return }
        textView.insertSnippet(body, replacing: NSRange(location: start, length: end - start))
    }
}

/// Finds the expression that ends right before a `.` in a syntax tree.
enum PostfixExpressionFinder {
    /// Node types that are a complete expression a `.` can follow.
    static let expressionTypes: Set<String> = [
        "identifier", "call_expression", "field_expression", "subscript_expression", "parenthesized_expression",
        "number_literal", "string_literal", "char_literal", "raw_string_literal", "qualified_identifier", "this"
    ]

    /// Node types that only complete an expression (the name after a `.`, an argument list, a closing
    /// bracket) and so are passed through on the way up.
    static let wrapperTypes: Set<String> = [
        "field_identifier", "namespace_identifier", "type_identifier", "argument_list", "string_content",
        "escape_sequence", "template_argument_list", "subscript_argument_list"
    ]

    /// The range of the largest expression that ends at `dot`, the offset of the `.`.
    ///
    /// Starting at the node covering the character before the `.`, walks up while the node still ends at
    /// `dot`, remembering the last expression node. Anything that is neither an expression nor a
    /// pass-through (a binary expression, an assignment, an `ERROR` node) ends the walk: `a + b.` is `b`.
    static func range(endingAt dot: Int, in nodes: [Node]) -> NSRange? {
        for start in nodes {
            var best: NSRange?
            var node: Node? = start
            while let current = node, NSMaxRange(current.range) == dot {
                let type = current.nodeType ?? ""
                if expressionTypes.contains(type) {
                    best = current.range
                } else if current.isNamed && !wrapperTypes.contains(type) {
                    break
                }
                node = current.parent
            }
            if let best { return best }
        }
        return nil
    }

    /// The expression that ends at `dot` in the tree of `client`.
    @MainActor
    static func range(endingAt dot: Int, in client: TreeSitterClient) -> NSRange? {
        guard dot > 0, let results = try? client.nodesAt(location: dot - 1) else { return nil }
        return range(endingAt: dot, in: results.map(\.node))
    }
}
