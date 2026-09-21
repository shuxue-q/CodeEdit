//
//  LSPHoverTrigger.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/17/26.
//

import AppKit
import Foundation

/// Decides whether a mouse location in the editor should trigger an LSP hover request.
///
/// Language servers such as clangd often return documentation for the enclosing symbol when the
/// cursor is on whitespace. Hover should only appear for function, variable, and file names.
enum LSPHoverTrigger {
    /// Same base set as completion word characters, plus `.` for names like `foo.h`.
    static let identifierCharacters = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "_$#."))

    /// Returns whether `offset` in `string` sits on an identifier or filename character.
    /// - Parameters:
    ///   - offset: A UTF-16 offset into `string`.
    ///   - string: The document text.
    /// - Returns: `true` when a hover request should be sent for this offset.
    static func shouldRequestHover(at offset: Int, in string: NSString) -> Bool {
        guard offset >= 0, offset < string.length else { return false }
        guard let scalar = Unicode.Scalar(string.character(at: offset)) else { return false }
        return identifierCharacters.contains(scalar)
    }

    /// Returns whether `point` is on the glyph at `glyphRect`, not trailing empty space on the line.
    /// - Parameters:
    ///   - point: A point in the text view's coordinate space.
    ///   - glyphRect: The layout rectangle of the character under consideration.
    /// - Returns: `true` when the pointer is on that glyph.
    static func glyphContainsMouse(point: NSPoint, glyphRect: NSRect) -> Bool {
        glyphRect.insetBy(dx: -0.5, dy: -2).contains(point)
    }
}
