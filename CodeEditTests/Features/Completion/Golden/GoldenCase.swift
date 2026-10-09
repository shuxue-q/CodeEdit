//
//  GoldenCase.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation
import LanguageServerProtocol
@testable import CodeEdit

/// One ranking scenario: the text before the cursor, what the language server offered, and what the
/// popup should show.
///
/// Cases run through ``CompletionIntentRecognizer`` and ``CompletionRanker`` without an editor, so they
/// pin the behavior the user sees: which intent is recognized, which three rows lead the list, and
/// whether a row is preselected.
struct GoldenCase {
    /// How a candidate came into the list.
    struct Item {
        var label: String
        var kind: LSPCompletionCategory = .variable
        var source: CompletionSource = .lsp
        /// The server asked for this item to be preselected.
        var preselect = false
        /// The server's sort key; items without one keep the order they are listed in.
        var sortText: String?
        /// The server's `detail`: the type of a variable or the return type of a function.
        var detail: String?

        /// A language-server item.
        static func lsp(
            _ label: String,
            _ kind: LSPCompletionCategory,
            detail: String? = nil,
            preselect: Bool = false
        ) -> Item {
            Item(label: label, kind: kind, preselect: preselect, detail: detail)
        }

        /// A postfix template offered after a `.`.
        static func postfix(_ label: String) -> Item {
            Item(label: label, kind: .snippet, source: .postfix)
        }

        /// A tree-sitter keyword.
        static func keyword(_ label: String) -> Item {
            Item(label: label, kind: .keyword, source: .keyword)
        }

        /// A tree-sitter snippet.
        static func snippet(_ label: String) -> Item {
            Item(label: label, kind: .snippet, source: .snippet)
        }

        /// An identifier from the document.
        static func word(_ label: String) -> Item {
            Item(label: label, kind: .text, source: .word)
        }
    }

    /// What `preselectedIndex` should say.
    enum Preselection: Equatable {
        /// No row stands out.
        case none
        /// The row with this label is the strong best match.
        case label(String)
    }

    var name: String
    /// The cursor's line up to the cursor. The trailing word is the typed prefix.
    var line: String
    /// The syntax-tree ancestry at the cursor, innermost first, as tree-sitter would report it.
    var nodeTypes: [String] = []
    var languageId = "cpp"
    var expectedIntent: CompletionIntent
    var items: [Item]
    /// The labels of the first three rows, best first. Fewer when fewer candidates survive.
    var expectedTop: [String]
    var expectedPreselection: Preselection = .none
    /// Past acceptances in this language and intent: `[label: count]`.
    var intentFrequencies: [String: Int] = [:]
    /// Labels accepted recently, by how many seconds ago.
    var acceptedSecondsAgo: [String: TimeInterval] = [:]
    /// Identifiers that already occur in the document.
    var documentIdentifiers: Set<String> = []
    var isExplicit = false
    /// The lines before `line`, for working out the slot (a `switch (…) {` before a `case`).
    var precedingText = ""
    /// The type the slot expects, given directly (for slots that need the syntax tree).
    var expectedType: String?
    /// The language server's answers to hover and signature help, to work the expected type out of the text.
    var slotTypes: SlotTypes?

    /// What hover and signature help would answer in a scenario.
    struct SlotTypes {
        /// The type of each symbol, by name.
        var symbols: [String: String] = [:]
        /// The type of the parameter the cursor is at in a call.
        var parameter: String?
    }

    /// The word at the end of `line`.
    var prefix: String {
        String(line.reversed().prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "#" }.reversed())
    }

    /// The candidates as the aggregator would hand them to the ranker.
    var candidates: [CompletionCandidate] {
        items.enumerated().map { index, item in
            let payload: CompletionPayload = item.source == .lsp
                ? .lsp(CompletionItem(label: item.label, preselect: item.preselect ? true : nil))
                : .plain(insertText: item.label)
            return CompletionCandidate(
                id: "\(index).\(item.label)",
                label: item.label,
                filterText: item.label,
                sortText: item.sortText ?? String(format: "%04d", index),
                kind: item.kind,
                source: item.source,
                detail: item.detail,
                payload: payload
            )
        }
    }

    /// The type the slot expects: given directly, or resolved from the text with the doubles in `slotTypes`.
    func resolveExpectedType(intent: CompletionIntent) async -> TypeText? {
        if let expectedType { return TypeText.parse(expectedType) }
        guard let slotTypes else { return nil }
        var environment = ExpectedTypeEnvironment()
        let text = precedingText + line
        let string = text as NSString
        environment.typeOfSymbol = { offset in
            var end = offset
            while end < string.length, let scalar = Unicode.Scalar(string.character(at: end)),
                  CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).contains(scalar) {
                end += 1
            }
            let symbol = string.substring(with: NSRange(location: offset, length: end - offset))
            return slotTypes.symbols[symbol].flatMap(TypeText.parse)
        }
        environment.activeParameterType = { _ in
            slotTypes.parameter.flatMap(LSPTypeExtraction.parameterType(fromLabel:))
        }
        return await ExpectedTypeResolver(environment: environment).resolve(
            text: text,
            prefixStart: string.length - (prefix as NSString).length,
            cursor: string.length,
            intent: intent,
            languageId: languageId
        )
    }

    /// Recognizes the intent, ranks the candidates, and returns both.
    func run(now: Date = Date()) async -> (intent: CompletionIntent, ranked: RankedCompletions) {
        let intent = CompletionIntentRecognizer { _ in nodeTypes }
            .recognize(at: 0, prefix: prefix, lineTextBeforeCursor: line, languageId: languageId)
        let lastAccepted = acceptedSecondsAgo.mapValues { now.addingTimeInterval(-$0) }
        let ranked = CompletionRanker.rank(
            CompletionDeduplicator.deduplicate(candidates),
            prefix: prefix,
            intent: intent,
            isExplicit: isExplicit,
            intentFrequencies: intentFrequencies,
            lastAccepted: lastAccepted,
            documentIdentifiers: documentIdentifiers,
            expectedType: await resolveExpectedType(intent: intent),
            now: now
        )
        return (intent, ranked)
    }
}
