//
//  NavigatorScroller.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/28/26.
//

import AppKit

/// An overlay-compatible scroller that draws an Xcode-style translucent knob.
///
/// The default AppKit knob renders as a nearly opaque dark bar in the navigator. Xcode's navigator
/// knob is a light, translucent capsule, so this scroller draws the knob itself with a dynamic
/// color that adapts to light and dark appearances.
final class NavigatorScroller: NSScroller {
    /// Translucent label-like knob color: black in light mode, white in dark mode.
    private static let knobColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
            return NSColor(white: 1, alpha: 0.3)
        }
        return NSColor(white: 0, alpha: 0.3)
    }

    /// Custom knob drawing must opt in, otherwise AppKit forces the legacy scroller style.
    override static var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnob() {
        let knobRect = rect(for: .knob)
        guard !knobRect.isEmpty else { return }
        let isVertical = bounds.height >= bounds.width
        let rect = knobRect.insetBy(dx: isVertical ? 3 : 2, dy: isVertical ? 2 : 3)
        guard rect.width > 0, rect.height > 0 else { return }
        let radius = min(rect.width, rect.height) / 2
        Self.knobColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
}
