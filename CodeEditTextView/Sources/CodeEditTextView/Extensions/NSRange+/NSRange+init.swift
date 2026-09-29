//
//  NSRange.swift
//  CodeEditTextView
//
//  Created by Khan Winter on 8/20/24.
//

import Foundation

public extension NSRange {
    @inline(__always)
    init(start: Int, end: Int) {
        self.init(location: start, length: end - start)
    }

    /// Intersects this range with `0..<length`. A range that starts past `length` becomes an empty range at `length`.
    func clamped(to length: Int) -> NSRange {
        guard length > 0 else {
            return NSRange(location: 0, length: 0)
        }
        let location = Swift.min(Swift.max(self.location, 0), length)
        let end = Swift.min(Swift.max(self.max, location), length)
        return NSRange(location: location, length: end - location)
    }
}
