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
        guard let start = lspPositionFrom(offset: nsRange.location),
              let end = lspPositionFrom(offset: nsRange.max) else {
            return nil
        }
        return LSPRange(start: start, end: end)
    }

    /// Computes the LSP position for a document offset, using UTF-16 code unit offsets as required by LSP.
    ///
    /// Positions come from the text storage, not the layout line index. Formatting filters apply several
    /// edits inside one `beginEditing` group, and the line index is not updated until that group ends.
    /// A column taken from the stale index can land past the end of the line. Clangd then drops the
    /// document and later completion requests fail with "non-added document".
    ///
    /// - Parameter offset: The offset in the text storage.
    /// - Returns: The zero-based line and character position. Offsets outside the buffer are clamped.
    func lspPositionFrom(offset: Int) -> Position? {
        let clamped = min(max(offset, 0), textStorage.length)
        // `mutableString` is the live buffer, including edits still inside `beginEditing`.
        return Self.lspPosition(at: clamped, in: textStorage.mutableString)
    }

    /// LSP line and character for a UTF-16 offset.
    ///
    /// Line breaks (`\n`, `\r\n`, `\r`, and Unicode separators) are not part of the line's character
    /// length. An offset on the break itself is the end of that line. An offset at the end of a buffer
    /// that ends in a break is the start of the empty trailing line.
    /// - Parameters:
    ///   - offset: A UTF-16 offset, clamped by the caller to `0...string.length`.
    ///   - string: The text to measure.
    /// - Returns: The zero-based position.
    static func lspPosition(at offset: Int, in string: NSString) -> Position {
        guard offset > 0 else {
            return Position(line: 0, character: 0)
        }
        var line = 0
        var index = 0
        while index < offset {
            var start = 0
            var lineEnd = 0
            var contentsEnd = 0
            string.getLineStart(
                &start,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: index, length: 0)
            )
            if offset < lineEnd {
                return Position(line: line, character: min(offset, contentsEnd) - start)
            }
            // A buffer with no trailing break ends on this line. A trailing break ends on the next one.
            if offset == lineEnd && lineEnd == string.length && contentsEnd == lineEnd {
                return Position(line: line, character: contentsEnd - start)
            }
            guard lineEnd > index else { break }
            line += 1
            index = lineEnd
        }
        return Position(line: line, character: 0)
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
