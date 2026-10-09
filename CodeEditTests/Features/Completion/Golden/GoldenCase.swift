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

        /// A language-server item.
        static func lsp(_ label: String, _ kind: LSPCompletionCategory, preselect: Bool = false) -> Item {
            Item(label: label, kind: kind, preselect: preselect)
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
                payload: payload
            )
        }
    }

    /// Recognizes the intent, ranks the candidates, and returns both.
    func run(now: Date = Date()) -> (intent: CompletionIntent, ranked: RankedCompletions) {
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
            now: now
        )
        return (intent, ranked)
    }
}
