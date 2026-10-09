//
//  DocumentWordTokenizer.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// Splits document text into identifiers for ``DocumentWordProvider``.
enum DocumentWordTokenizer {
    /// Words shorter than this are not worth completing.
    static let minimumLength = 3
    /// The most distinct words kept per document; the most frequent win.
    static let maximumWords = 5_000

    /// The identifiers in `text` with how often each occurs.
    ///
    /// An identifier is a run of letters, digits and underscores that does not start with a digit.
    /// Anything outside ASCII counts as a letter so non-Latin identifiers survive. Pure and
    /// `Sendable`-friendly: call it from a background task on a snapshot of the text.
    static func words(in text: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        var current: [UInt8] = []
        var startsWithDigit = false

        func finish() {
            defer {
                current.removeAll(keepingCapacity: true)
                startsWithDigit = false
            }
            guard current.count >= minimumLength, !startsWithDigit else { return }
            if let word = String(bytes: current, encoding: .utf8) {
                counts[word, default: 0] += 1
            }
        }

        for byte in text.utf8 {
            let isWordByte = (byte >= 0x30 && byte <= 0x39)   // 0-9
                || (byte >= 0x41 && byte <= 0x5A)             // A-Z
                || (byte >= 0x61 && byte <= 0x7A)             // a-z
                || byte == 0x5F                               // _
                || byte >= 0x80
            if isWordByte {
                if current.isEmpty { startsWithDigit = byte >= 0x30 && byte <= 0x39 }
                current.append(byte)
            } else {
                finish()
            }
        }
        finish()

        guard counts.count > maximumWords else { return counts }
        let kept = counts.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
        }.prefix(maximumWords)
        return Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }
}
