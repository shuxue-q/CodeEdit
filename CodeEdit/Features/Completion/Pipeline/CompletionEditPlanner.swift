//
//  CompletionEditPlanner.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// One text replacement in document (UTF-16) coordinates.
struct CompletionTextEdit: Equatable {
    /// The replaced range.
    var range: NSRange
    /// The replacement text.
    var newText: String

    /// How many UTF-16 units the document grows by when this edit is applied.
    var lengthDelta: Int {
        (newText as NSString).length - range.length
    }
}

/// Orders the edits of one completion acceptance so every range stays valid while they are applied.
///
/// A server item has a primary edit (the text that replaces the typed prefix) and may carry
/// `additionalTextEdits`, such as clangd's `#include` line above the cursor. The additional edits
/// are applied first, from the end of the document backwards, so earlier offsets stay valid; the
/// primary edit goes last, shifted by whatever the earlier edits added. Applying the primary edit
/// last also leaves the caret (or a snippet's tab stops) on the completed symbol.
enum CompletionEditPlanner {
    /// The result of ``plan(primary:additional:)``.
    struct Plan: Equatable {
        /// The additional edits, in the order they should be applied.
        var additional: [CompletionTextEdit]
        /// The primary edit's range after the additional edits have been applied.
        var primaryRange: NSRange
    }

    /// Plans the order of `additional` edits relative to the `primary` range.
    ///
    /// Edits that overlap the primary range are dropped: they cannot be applied independently of it.
    /// Several insertions at the same offset keep the order the server listed them in.
    static func plan(primary: NSRange, additional: [CompletionTextEdit]) -> Plan {
        var independent: [(index: Int, edit: CompletionTextEdit)] = []
        var shift = 0
        for (index, edit) in additional.enumerated() {
            if edit.range.max <= primary.location {
                shift += edit.lengthDelta
                independent.append((index, edit))
            } else if edit.range.location >= primary.max {
                independent.append((index, edit))
            }
        }
        // Later offsets first. Equal offsets are applied in reverse list order so the document ends
        // up with the insertions in list order.
        independent.sort { lhs, rhs in
            if lhs.edit.range.location != rhs.edit.range.location {
                return lhs.edit.range.location > rhs.edit.range.location
            }
            return lhs.index > rhs.index
        }
        return Plan(
            additional: independent.map(\.edit),
            primaryRange: NSRange(location: primary.location + shift, length: primary.length)
        )
    }
}
