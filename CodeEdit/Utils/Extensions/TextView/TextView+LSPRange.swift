//
//  TextView+LSPRange.swift
//  CodeEdit
//
//  Created by Khan Winter on 9/21/24.
//

import AppKit
import CodeEditTextView
import LanguageServerProtocol

extension TextView {
    func lspRangeFrom(nsRange: NSRange) -> LSPRange? {
        guard let startLine = layoutManager.textLineForOffset(nsRange.location),
              let endLine = layoutManager.textLineForOffset(nsRange.max) else {
            return nil
        }
        return LSPRange(
            start: Position(line: startLine.index, character: nsRange.location - startLine.range.location),
            end: Position(line: endLine.index, character: nsRange.max - endLine.range.location)
        )
    }

    /// Computes the LSP position for a document offset, using UTF-16 code unit offsets as required by LSP.
    /// - Parameter offset: The offset in the text storage.
    /// - Returns: The zero-based line and character position, or `nil` if the offset is invalid.
    func lspPositionFrom(offset: Int) -> Position? {
        guard let linePosition = layoutManager.textLineForOffset(offset) else {
            return nil
        }
        return Position(line: linePosition.index, character: offset - linePosition.range.location)
    }

    /// Computes the document range for an LSP range, using UTF-16 code unit offsets as required by LSP.
    /// - Parameter lspRange: The zero-based line/character range from the language server.
    /// - Returns: The equivalent range in the text storage, or `nil` if the range is invalid.
    func nsRangeFrom(lspRange: LSPRange) -> NSRange? {
        guard let startLine = layoutManager.textLineForIndex(lspRange.start.line),
              let endLine = layoutManager.textLineForIndex(lspRange.end.line) else {
            return nil
        }
        let start = startLine.range.location + min(lspRange.start.character, startLine.range.length)
        let end = endLine.range.location + min(lspRange.end.character, endLine.range.length)
        guard end >= start else { return nil }
        return NSRange(location: start, length: end - start)
    }
}
