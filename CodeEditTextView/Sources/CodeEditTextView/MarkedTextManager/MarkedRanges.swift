//
//  MarkedRanges.swift
//  CodeEditTextView
//
//  Created by Khan Winter on 4/17/25.
//

import AppKit

/// Struct for passing attribute and range information easily down into line fragments, typesetters without
/// requiring a reference to the marked text manager.
public struct MarkedRanges {
    let ranges: [NSRange]
    let attributes: [NSAttributedString.Key: Any]

    /// Drops marks that start past `maxLength` and shortens any that would run past it.
    /// Ranges are relative to the line substring passed to the typesetter.
    func clipped(to maxLength: Int) -> MarkedRanges? {
        guard maxLength > 0 else { return nil }
        let clippedRanges = ranges.compactMap { mark -> NSRange? in
            guard mark.location >= 0, mark.location < maxLength else { return nil }
            let length = min(mark.length, maxLength - mark.location)
            guard length > 0 else { return nil }
            return NSRange(location: mark.location, length: length)
        }
        guard !clippedRanges.isEmpty else { return nil }
        return MarkedRanges(ranges: clippedRanges, attributes: attributes)
    }
}
