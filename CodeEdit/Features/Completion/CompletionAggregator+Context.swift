//
//  CompletionAggregator+Context.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import AppKit
import CodeEditSourceEditor
import CodeEditTextView

// MARK: - Context

extension CompletionAggregator {
    func buildContext(string: NSString, location: Int, isExplicit: Bool) -> CompletionContext {
        var prefixRange = wordRange(in: string, at: location)
        var prefix = string.substring(with: prefixRange)
        let lineStart = lineStart(in: string, before: location)
        let lineTextBeforeCursor = string.substring(with: NSRange(location: lineStart, length: location - lineStart))
        let languageId = document?.getLanguage().id.rawValue ?? ""
        let recognizer = CompletionIntentRecognizer(treeSitterClient: treeSitterClient)
        let intent = recognizer.recognize(
            at: location,
            prefix: prefix,
            lineTextBeforeCursor: lineTextBeforeCursor,
            languageId: languageId
        )
        prefixRange = completionWordRange(in: string, at: location, intent: intent, languageId: languageId)
        prefix = string.substring(with: prefixRange)

        return CompletionContext(
            prefix: prefix,
            prefixRange: prefixRange,
            triggerCharacter: location > 0 ? string.substring(with: NSRange(location: location - 1, length: 1)) : nil,
            intent: intent,
            languageId: languageId,
            documentText: string as String,
            cursorOffset: location,
            isExplicit: isExplicit
        )
    }

    func wordRange(in string: NSString, at location: Int) -> NSRange {
        var start = location
        while start > 0,
              let scalar = Unicode.Scalar(string.character(at: start - 1)),
              Self.wordCharacters.contains(scalar) {
            start -= 1
        }
        return NSRange(location: start, length: location - start)
    }

    /// The range of the word being completed. In a Dart string, `$` starts an interpolated name rather
    /// than being part of one (`'Hi $na`, `'$a$b`), so the word starts after the last `$`.
    func completionWordRange(
        in string: NSString,
        at location: Int,
        intent: CompletionIntent,
        languageId: String
    ) -> NSRange {
        let range = wordRange(in: string, at: location)
        guard intent == .variableReference, DartKeywords.languageIds.contains(languageId) else { return range }
        let dollar = string.range(of: "$", options: .backwards, range: range)
        guard dollar.location != NSNotFound else { return range }
        let start = dollar.location + dollar.length
        return NSRange(location: start, length: range.location + range.length - start)
    }

    /// ``completionWordRange(in:at:intent:languageId:)`` for the request made with `context`.
    func completionWordRange(in string: NSString, at location: Int, for context: CompletionContext) -> NSRange {
        completionWordRange(in: string, at: location, intent: context.intent, languageId: context.languageId)
    }

    func lineStart(in string: NSString, before location: Int) -> Int {
        var start = location
        while start > 0 && string.character(at: start - 1) != 0x0A {
            start -= 1
        }
        return start
    }

    func rank(
        _ candidates: [CompletionCandidate],
        prefix: String,
        context: CompletionContext
    ) -> RankedCompletions {
        let deduped = CompletionDeduplicator.deduplicate(candidates)
        return CompletionRanker.rank(
            deduped,
            prefix: prefix,
            intent: context.intent,
            languageId: context.languageId,
            isExplicit: context.isExplicit,
            frequencies: statistics.languageFrequencies,
            intentFrequencies: statistics.intentFrequencies,
            lastAccepted: statistics.lastAccepted,
            receiverFrequencies: statistics.receiverFrequencies,
            receiverLastAccepted: statistics.receiverLastAccepted,
            documentIdentifiers: context.documentIdentifiers,
            expectedType: context.expectedType
        )
    }

    /// Adds the results that arrived after the window opened. A late language server answer also says
    /// whether its list is incomplete.
    func mergeLateResults() {
        for late in lateResults {
            for candidate in late.candidates { candidateOwners[candidate.id] = late.provider }
            rawCandidates.append(contentsOf: late.candidates)
            if late.provider === lspProvider {
                serverList.isIncomplete = lspProvider.lastListIsIncomplete
            }
        }
        lateResults = []
    }

    /// Adds document words once the typed prefix is long enough, when the request was made too early
    /// to ask for them.
    func mergeWordCandidatesIfNeeded(context: CompletionContext) {
        guard !wordCandidatesGathered,
              context.prefix.count >= DocumentWordProvider.minimumPrefixLength,
              let words = wordProvider.cachedCandidates(for: context) else {
            return
        }
        wordCandidatesGathered = true
        for word in words { candidateOwners[word.id] = wordProvider }
        rawCandidates.append(contentsOf: words)
    }
}
