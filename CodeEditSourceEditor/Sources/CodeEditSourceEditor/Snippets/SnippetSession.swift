//
//  SnippetSession.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit Contributors on 9/29/26.
//

import Foundation

/// Tracks the tab stops of an inserted snippet while the user moves through them.
///
/// Ranges are document offsets and follow edits made while the session is active: typing inside
/// a placeholder grows or shrinks it, edits before it shift it.
struct SnippetSession: Equatable {
    /// Tab-stop ranges in navigation order. The last group is the final cursor position.
    private(set) var groups: [[NSRange]]
    /// The index into `groups` of the tab stop being edited.
    private(set) var activeGroup: Int = 0
    /// The whole inserted snippet. Selections outside it end the session.
    private(set) var extent: NSRange

    /// Creates a session for `snippet` inserted at `location`. Returns `nil` when the snippet has no
    /// numbered tab stops to move through.
    init?(snippet: ParsedSnippet, location: Int) {
        guard snippet.hasPlaceholders else { return nil }
        groups = snippet.navigationGroups.map { group in
            group.map { NSRange(location: $0.location + location, length: $0.length) }
        }
        extent = NSRange(location: location, length: (snippet.text as NSString).length)
    }

    /// The ranges of the tab stop being edited.
    var activeRanges: [NSRange] {
        groups[activeGroup]
    }

    /// `true` when the active tab stop is the final cursor position.
    var isAtFinalStop: Bool {
        activeGroup == groups.count - 1
    }

    /// Ranges of every placeholder the user can still move to, with whether it is the active one.
    /// The final stop is not a placeholder and is left out.
    var placeholderRanges: [(range: NSRange, isActive: Bool)] {
        groups.indices.dropLast().flatMap { index in
            groups[index].map { (range: $0, isActive: index == activeGroup) }
        }
    }

    /// Moves to the next (or previous) tab stop. Returns `false` when there is none in that direction.
    mutating func move(backwards: Bool) -> Bool {
        let next = activeGroup + (backwards ? -1 : 1)
        guard groups.indices.contains(next) else { return false }
        activeGroup = next
        return true
    }

    /// Updates the ranges after `range` (in pre-edit offsets) was replaced by `length` UTF-16 units.
    ///
    /// The active placeholder absorbs edits touching either of its ends, so typing at the start or end
    /// of it extends it. Other placeholders only absorb edits strictly inside them. Placeholders the
    /// edit cuts across are dropped.
    ///
    /// - Returns: `false` when the edit crosses the snippet's boundary and the session should end.
    mutating func applyEdit(replacing range: NSRange, length: Int) -> Bool {
        guard let newExtent = Self.adjust(extent, replacing: range, length: length, inclusive: true) else {
            return false
        }
        extent = newExtent
        for groupIndex in groups.indices {
            let inclusive = groupIndex == activeGroup
            groups[groupIndex] = groups[groupIndex].compactMap {
                Self.adjust($0, replacing: range, length: length, inclusive: inclusive)
            }
        }
        // A tab stop whose ranges were all cut is skipped. Keep the final stop.
        var index = 0
        while index < groups.count - 1 {
            if groups[index].isEmpty {
                groups.remove(at: index)
                if activeGroup > index { activeGroup -= 1 }
            } else {
                index += 1
            }
        }
        if groups[groups.count - 1].isEmpty {
            groups[groups.count - 1] = [NSRange(location: extent.max, length: 0)]
        }
        activeGroup = min(activeGroup, groups.count - 1)
        return groups.count > 1
    }

    /// Returns `true` when every range lies within the snippet.
    func contains(selections: [NSRange]) -> Bool {
        !selections.isEmpty && selections.allSatisfy { $0.location >= extent.location && $0.max <= extent.max }
    }

    /// Adjusts `target` for `range` (pre-edit) being replaced by `length` units. `nil` when the edit
    /// partially overlaps `target`.
    static func adjust(_ target: NSRange, replacing range: NSRange, length: Int, inclusive: Bool) -> NSRange? {
        let delta = length - range.length
        let isInside = range.location >= target.location && range.max <= target.max
        let absorbs = isInside && (
            inclusive
            || range.length > 0
            || (range.location > target.location && range.location < target.max)
        )
        if absorbs {
            return NSRange(location: target.location, length: target.length + delta)
        }
        if range.max <= target.location {
            return NSRange(location: target.location + delta, length: target.length)
        }
        if range.location >= target.max {
            return target
        }
        return nil
    }
}
