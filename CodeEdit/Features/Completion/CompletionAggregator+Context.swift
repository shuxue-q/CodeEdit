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
        let prefixRange = wordRange(in: string, at: location)
        let prefix = string.substring(with: prefixRange)
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
