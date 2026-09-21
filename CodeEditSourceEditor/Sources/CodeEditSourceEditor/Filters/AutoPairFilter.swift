//
//  AutoPairFilter.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit Contributors on 9/16/26.
//

import Foundation
import TextFormation
import TextStory

/// Automatically closes brackets and quotes, handles overtyping (skip out),
/// Tab key jumping out of pairs, and backspace deletion of empty pairs.
struct AutoPairFilter: Filter {
    /// Pairs of opening and closing characters.
    private static let openToClose: [String: String] = [
        "\"": "\"",
        "'": "'",
        "(": ")",
        "[": "]",
        "{": "}"
    ]

    /// Closing characters that can be jumped over via Tab or overtyping.
    private static let jumpOutCharacters: Set<String> = [">", "\"", "'", ")", "]", "}"]

    func processMutation(
        _ mutation: TextMutation,
        in interface: TextInterface,
        with providers: WhitespaceProviders
    ) -> FilterAction {
        if mutation.string == "\t" {
            return handleTab(mutation, in: interface)
        }
        if mutation.string.isEmpty && mutation.range.length == 1 {
            return handleDelete(mutation, in: interface)
        }
        guard mutation.range.length == 0, mutation.string.count == 1 else {
            return .none
        }

        let typed = mutation.string
        let location = mutation.range.location

        if let overtypeAction = handleOvertype(typed: typed, location: location, in: interface) {
            return overtypeAction
        }
        return handleAutoClose(typed: typed, location: location, limit: mutation.limit, in: interface)
    }

    private func handleOvertype(typed: String, location: Int, in interface: TextInterface) -> FilterAction? {
        guard Self.jumpOutCharacters.contains(typed), location < interface.length else {
            return nil
        }
        if let nextChar = interface.substring(from: NSRange(location: location, length: 1)),
           nextChar == typed {
            interface.selectedRange = NSRange(location: location + 1, length: 0)
            return .discard
        }
        return nil
    }

    private func handleAutoClose(
        typed: String,
        location: Int,
        limit: Int,
        in interface: TextInterface
    ) -> FilterAction {
        if typed == "<", location >= 8 {
            var lineStart = location
            while lineStart > 0,
                  let prevChar = interface.substring(from: NSRange(location: lineStart - 1, length: 1)),
                  prevChar != "\n" {
                lineStart -= 1
            }
            if let linePrefix = interface.substring(from: NSRange(location: lineStart, length: location - lineStart)),
               linePrefix.trimmingCharacters(in: .whitespaces) == "#include" {
                interface.applyMutation(TextMutation(insert: "<>", at: location, limit: limit))
                interface.selectedRange = NSRange(location: location + 1, length: 0)
                return .discard
            }
        }

        guard let close = Self.openToClose[typed] else { return .none }
        if typed == "'", location > 0 {
            if let prevChar = interface.substring(from: NSRange(location: location - 1, length: 1)),
               let scalar = prevChar.unicodeScalars.first,
               CharacterSet.alphanumerics.contains(scalar) {
                return .none
            }
        }

        let pairString = typed + close
        interface.applyMutation(TextMutation(insert: pairString, at: location, limit: limit))
        interface.selectedRange = NSRange(location: location + typed.utf16.count, length: 0)
        return .discard
    }

    private func handleTab(_ mutation: TextMutation, in interface: TextInterface) -> FilterAction {
        if mutation.range.length == 0 {
            let location = mutation.range.location
            if location < interface.length,
               let nextChar = interface.substring(from: NSRange(location: location, length: 1)),
               Self.jumpOutCharacters.contains(nextChar) {
                interface.selectedRange = NSRange(location: location + 1, length: 0)
                return .discard
            }
        } else if mutation.range.length > 0 {
            let endLocation = mutation.range.max
            if endLocation < interface.length,
               let selectedText = interface.substring(from: mutation.range),
               !selectedText.contains("\n"),
               let nextChar = interface.substring(from: NSRange(location: endLocation, length: 1)),
               Self.jumpOutCharacters.contains(nextChar) {
                interface.selectedRange = NSRange(location: endLocation + 1, length: 0)
                return .discard
            }
        }

        return .none
    }

    private func handleDelete(_ mutation: TextMutation, in interface: TextInterface) -> FilterAction {
        let location = mutation.range.location
        guard location < interface.length,
              let deletedChar = interface.substring(from: mutation.range) else {
            return .none
        }

        let expectedClose = deletedChar == "<" ? ">" : Self.openToClose[deletedChar]
        guard let close = expectedClose, location + 1 + close.utf16.count <= interface.length else {
            return .none
        }

        if let nextChar = interface.substring(from: NSRange(location: location + 1, length: close.utf16.count)),
           nextChar == close {
            let fullPairRange = NSRange(location: location, length: 1 + close.utf16.count)
            interface.applyMutation(
                TextMutation(
                    delete: fullPairRange,
                    limit: mutation.limit
                )
            )
            interface.selectedRange = NSRange(location: location, length: 0)
            return .discard
        }

        return .none
    }
}
