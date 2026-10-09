//
//  DocumentWordProvider.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import AppKit
import CodeEditSourceEditor
import CodeEditTextView

/// Offers identifiers that already appear in the current document, so completion still helps when no
/// language server answers (or while it is still starting).
///
/// Words are tokenized off the main actor from a snapshot of the text and cached per content, so a
/// keystroke that only extends the typed prefix never tokenizes again. Words are offered with a
/// prefix of at least two characters (or on an explicit request), only where a plain name makes
/// sense (see ``CompletionIntentPolicy/documentWordIntents``), and never include the word being
/// typed unless it also occurs elsewhere.
@MainActor
final class DocumentWordProvider: CompletionProvider {
    let source: CompletionSource = .word
    /// Zero: the words are cached, and a first tokenization is fast.
    let deadline: Duration = .zero

    /// Characters that make up a word when looking for the word under the cursor.
    private static let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))

    /// How many times a document was tokenized, for tests that check the cache.
    private(set) var tokenizationCount = 0

    /// The most recent tokenization and the text it was made from.
    private var cache: (key: Key, words: [String: Int])?
    /// A tokenization in flight, so concurrent requests for the same text share one pass.
    private var inFlight: (key: Key, task: Task<[String: Int], Never>)?

    private struct Key: Equatable {
        let length: Int
        let hash: Int

        init(_ text: String) {
            length = text.utf8.count
            hash = text.hashValue
        }
    }

    // MARK: - Words

    /// The identifiers in `text` with their occurrence counts, tokenized off the main actor and cached.
    func words(in text: String) async -> [String: Int] {
        let key = Key(text)
        if let cache, cache.key == key { return cache.words }
        if let inFlight, inFlight.key == key { return await inFlight.task.value }

        tokenizationCount += 1
        let task = Task.detached(priority: .userInitiated) { DocumentWordTokenizer.words(in: text) }
        inFlight = (key, task)
        let words = await task.value
        if inFlight?.key == key {
            cache = (key, words)
            inFlight = nil
        }
        return words
    }

    // MARK: - CompletionProvider

    func candidates(for context: CompletionContext, textView: TextViewController) async -> [CompletionCandidate] {
        guard CompletionIntentPolicy.documentWordIntents.contains(context.intent) else { return [] }
        guard context.isExplicit || context.prefix.count >= Self.minimumPrefixLength else {
            // Too early to offer words, but the next keystroke will want them: tokenize in the background.
            prewarm(context.documentText)
            return []
        }
        let words = await words(in: context.documentText)
        guard !Task.isCancelled else { return [] }
        return Self.candidates(from: words, context: context)
    }

    /// The prefix length from which words are offered for a typing-triggered request.
    static let minimumPrefixLength = 2

    /// Word candidates from the most recent tokenization, without waiting for a new one.
    ///
    /// Used when the typed prefix grows past ``minimumPrefixLength`` inside an open window, where the
    /// snapshot taken a keystroke earlier is accurate enough. `nil` while nothing has been tokenized yet.
    func cachedCandidates(for context: CompletionContext) -> [CompletionCandidate]? {
        guard CompletionIntentPolicy.documentWordIntents.contains(context.intent),
              let cache else {
            return nil
        }
        return Self.candidates(from: cache.words, context: context)
    }

    /// Starts tokenizing `text` so the result is cached for the next request.
    private func prewarm(_ text: String) {
        Task { _ = await words(in: text) }
    }

    /// Turns `words` into candidates matching the typed prefix, leaving out the word under the cursor
    /// unless the document uses it elsewhere too.
    private static func candidates(from words: [String: Int], context: CompletionContext) -> [CompletionCandidate] {
        let wordAtCursor = word(in: context.documentText, around: context.cursorOffset)
        return words.keys.sorted().compactMap { word in
            if word == wordAtCursor, words[word] == 1 { return nil }
            guard FuzzyMatcher.match(pattern: context.prefix, candidate: word) != nil else { return nil }
            return CompletionCandidate(
                id: "word.\(word)",
                label: word,
                filterText: word,
                sortText: word,
                kind: .text,
                source: .word,
                payload: .plain(insertText: word)
            )
        }
    }

    func apply(_ candidate: CompletionCandidate, textView: TextViewController, cursorPosition: CursorPosition?) {
        guard case .plain(let text) = candidate.payload,
              let cursorPosition,
              let resolved = textView.resolveCursorPosition(cursorPosition) else {
            return
        }
        let location = resolved.range.location
        let string = textView.textView.textStorage.string as NSString
        var wordStart = location
        while wordStart > 0,
              let scalar = Unicode.Scalar(string.character(at: wordStart - 1)),
              Self.wordCharacters.contains(scalar) {
            wordStart -= 1
        }
        textView.textView.replaceCharacters(in: NSRange(location: wordStart, length: location - wordStart), with: text)
    }

    // MARK: - Helpers

    /// The whole word touching `offset`, including characters after the cursor.
    static func word(in text: String, around offset: Int) -> String {
        let string = text as NSString
        guard offset >= 0, offset <= string.length else { return "" }
        var start = offset
        while start > 0, isWordCharacter(string.character(at: start - 1)) { start -= 1 }
        var end = offset
        while end < string.length, isWordCharacter(string.character(at: end)) { end += 1 }
        return string.substring(with: NSRange(location: start, length: end - start))
    }

    private static func isWordCharacter(_ unit: unichar) -> Bool {
        Unicode.Scalar(unit).map(wordCharacters.contains) ?? false
    }
}
