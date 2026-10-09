//
//  ChainCompletionProvider.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageServerProtocol

/// Chain completion: members reachable through one symbol that have the type the slot expects.
///
/// Where `std::string label = ` expects a string and the file has a `Car car`, the chain
/// `car.label` is offered. For the best few symbols whose type has members, the provider asks the
/// language server what follows `symbol.` in a scratch copy of the document (see ``ChainScratchServer``),
/// keeps the members whose type fits, and offers each as one item that inserts `symbol.member`. The
/// user's buffer is never edited.
///
/// This is a second stage after the regular providers rather than one of them: it needs their symbols.
/// ``CompletionAggregator`` calls ``chainCandidates(from:context:budget:)`` for chain requests.
@MainActor
final class ChainCompletionProvider: CompletionProvider {
    /// The most symbols asked about.
    static let maximumFirstLevelSymbols = 8
    /// The longest the whole chain stage may take, counted from the start of the request.
    static let budget: Duration = .milliseconds(800)

    let source: CompletionSource = .lsp
    let deadline: Duration = .zero

    /// A symbol that can be followed by `.` or `->`.
    struct FirstLevelSymbol: Equatable {
        /// The text inserted for the symbol: `car`, or `engine()` for a getter without parameters.
        let expression: String
        /// `.` or `->`.
        let accessor: String
    }

    /// Makes the scratch server for the document, or `nil` when there is no language server.
    private let makeServer: () -> ChainScratchServer?
    private var server: ChainScratchServer?
    /// How each offered candidate is applied, keyed by candidate id.
    private var applications: [String: CompletionPayload] = [:]

    /// Creates a provider whose scratch server comes from `makeServer`, called when it is first needed.
    init(makeServer: @escaping () -> ChainScratchServer?) {
        self.makeServer = makeServer
    }

    /// Closes the scratch document on the server.
    func shutdown() {
        guard let server else { return }
        self.server = nil
        Task { await server.closeScratch() }
    }

    // MARK: - CompletionProvider

    /// Chain completion is a second stage; as a regular provider it offers nothing.
    func candidates(for context: CompletionContext, textView: TextViewController) async -> [CompletionCandidate] {
        []
    }

    func apply(_ candidate: CompletionCandidate, textView: TextViewController, cursorPosition: CursorPosition?) {
        guard let payload = applications[candidate.id],
              let cursorPosition,
              let resolved = textView.resolveCursorPosition(cursorPosition) else {
            return
        }
        let location = resolved.range.location
        let string = textView.textView.textStorage.string as NSString
        var wordStart = location
        while wordStart > 0,
              let scalar = Unicode.Scalar(string.character(at: wordStart - 1)),
              CompletionAggregator.wordCharacters.contains(scalar) {
            wordStart -= 1
        }
        let range = NSRange(location: wordStart, length: location - wordStart)
        switch payload {
        case .snippet(let body): textView.insertSnippet(body, replacing: range)
        case .plain(let text): textView.textView.replaceCharacters(in: range, with: text)
        case .lsp: return
        }
    }

    // MARK: - Chains

    /// The chains for the slot at the cursor.
    ///
    /// - Parameters:
    ///   - candidates: The regular candidates, best first; the symbols to chain through are taken from them.
    ///   - context: The request. Without an expected type there is nothing to match, and nothing is offered.
    ///   - budget: How long the stage may take. Chains found by then are returned; the rest are dropped.
    func chainCandidates(
        from candidates: [CompletionCandidate],
        context: CompletionContext,
        budget: Duration
    ) async -> [CompletionCandidate] {
        applications = [:]
        guard let expected = context.expectedType, budget > .zero,
              let server = currentServer() else {
            return []
        }
        let symbols = Self.firstLevelSymbols(in: candidates, limit: Self.maximumFirstLevelSymbols)
        guard !symbols.isEmpty else { return [] }

        let collector = Collector()
        let work = Task { @MainActor in
            for symbol in symbols {
                guard !Task.isCancelled else { return }
                let found = await self.members(of: symbol, expected: expected, context: context, server: server)
                collector.candidates.append(contentsOf: found)
            }
        }
        _ = await awaitValue(of: work, upTo: budget)
        work.cancel()
        for candidate in collector.candidates {
            applications[candidate.id] = candidate.payload
        }
        return collector.candidates
    }

    /// Candidates found so far, shared between the work task and the caller that may stop waiting for it.
    @MainActor
    private final class Collector {
        var candidates: [CompletionCandidate] = []
    }

    private func currentServer() -> ChainScratchServer? {
        if server == nil { server = makeServer() }
        return server
    }

    /// The members of `symbol` whose type fits `expected`, as chain candidates.
    private func members(
        of symbol: FirstLevelSymbol,
        expected: TypeText,
        context: CompletionContext,
        server: ChainScratchServer
    ) async -> [CompletionCandidate] {
        let text = context.documentText as NSString
        let start = context.prefixRange.location
        let prefix = symbol.expression + symbol.accessor
        let scratch = text.replacingCharacters(in: context.prefixRange, with: prefix)
        let cursor = start + (prefix as NSString).length
        guard let position = Self.position(of: cursor, in: scratch as NSString) else { return [] }
        do {
            try await server.updateScratch(text: scratch)
            let response = try await server.completeInScratch(at: position)
            return zip(response.items, response.scores).compactMap { item, score in
                Self.chain(through: symbol, member: item, score: score, expected: expected)
            }
        } catch {
            return []
        }
    }

    // MARK: - Pure helpers

    /// The symbols among `candidates` that can be followed by `.` or `->`: variables and getters without
    /// parameters whose type has members. In the given order, at most `limit`.
    static func firstLevelSymbols(in candidates: [CompletionCandidate], limit: Int) -> [FirstLevelSymbol] {
        var symbols: [FirstLevelSymbol] = []
        for candidate in candidates where symbols.count < limit {
            guard candidate.source == .lsp,
                  candidate.kind == .variable || candidate.kind == .function,
                  case .lsp(let item) = candidate.payload,
                  let type = CandidateTypeParser.resultType(of: candidate), type.isClassLike else {
                continue
            }
            let inserted = insertedText(of: item)
            guard !inserted.contains("$"), !inserted.hasPrefix("~"), !inserted.contains("operator"),
                  inserted.range(of: #"^[A-Za-z_]\w*(?:\(\))?$"#, options: .regularExpression) != nil else {
                continue
            }
            let symbol = FirstLevelSymbol(expression: inserted, accessor: type.pointerDepth == 1 ? "->" : ".")
            if !symbols.contains(symbol) { symbols.append(symbol) }
        }
        return symbols
    }

    /// The text accepting `item` inserts: its text edit, its insert text, or its label.
    static func insertedText(of item: CompletionItem) -> String {
        let text: String
        switch item.textEdit {
        case .optionA(let edit)?: text = edit.newText
        case .optionB(let edit)?: text = edit.newText
        case nil: text = item.insertText ?? item.label
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// The chain candidate for `member`, a completion item after `symbol.`, if its type fits `expected`.
    static func chain(
        through symbol: FirstLevelSymbol,
        member item: CompletionItem,
        score: Double?,
        expected: TypeText
    ) -> CompletionCandidate? {
        let category = LSPCompletionEntry.category(for: item)
        let name = CompletionDeduplicator.normalizedLabel(item.label)
        guard category == .variable || category == .function, !name.hasPrefix("~"), !name.contains("operator") else {
            return nil
        }
        let prefix = symbol.expression + symbol.accessor
        let memberText = insertedText(of: item)
        let payload: CompletionPayload = item.insertTextFormat == .snippet && memberText.contains("$")
            ? .snippet(body: escapedLiteral(prefix) + memberText)
            : .plain(insertText: prefix + memberText)
        let candidate = CompletionCandidate(
            id: "chain.\(prefix)\(name)",
            label: prefix + name,
            filterText: prefix + name,
            score: score,
            kind: category,
            source: .lsp,
            detail: item.detail,
            payload: payload
        )
        guard let type = CandidateTypeParser.resultType(of: candidate), expected.match(type) != .none else {
            return nil
        }
        return candidate
    }

    /// `text` as literal text inside a snippet body, where `$`, `}` and `\` are special.
    private static func escapedLiteral(_ text: String) -> String {
        var escaped = ""
        for character in text {
            if "\\$}".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }

    /// The LSP position (zero-based line, UTF-16 column) of `offset` in `text`.
    static func position(of offset: Int, in text: NSString) -> Position? {
        guard offset >= 0, offset <= text.length else { return nil }
        var line = 0
        var lineStart = 0
        var index = 0
        while index < offset {
            if text.character(at: index) == 0x0A {
                line += 1
                lineStart = index + 1
            }
            index += 1
        }
        return Position(line: line, character: offset - lineStart)
    }
}
