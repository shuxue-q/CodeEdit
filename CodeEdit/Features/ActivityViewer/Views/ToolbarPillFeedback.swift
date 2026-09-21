//
//  ToolbarPillFeedback.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/20/26.
//

import SwiftUI

/// Horizontal capsule hover and selection feedback for toolbar icon buttons
/// inside an ``XcodeCapsuleContainer``, matching Xcode's toolbar. The pill is
/// 26pt tall and centered in the icon's 37pt-wide, 40pt-tall cell, its center
/// coinciding with the enclosing 40pt-tall capsule's center.
private struct ToolbarPillFeedbackModifier: ViewModifier {
    /// Whether the button is in a selected (active) state.
    var isSelected: Bool
    /// Width of the feedback pill. Narrower than the default for single-icon capsules.
    var pillWidth: CGFloat = 40

    @Environment(\.isEnabled)
    private var isEnabled

    @State private var isHovered: Bool = false

    func body(content: Content) -> some View {
        content
            .frame(width: 37, height: 40)
            .background {
                Capsule()
                    .fill(fillColor)
                    .frame(width: pillWidth, height: 26)
                    .opacity(showsPill ? 1 : 0)
            }
            .contentShape(Capsule())
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: showsPill)
    }

    private var showsPill: Bool {
        isSelected || (isHovered && isEnabled)
    }

    private var fillColor: Color {
        Color.primary.opacity(isSelected ? 0.14 : 0.08)
    }
}

extension View {
    /// Gives a toolbar icon button a capsule-shaped hover/selection indicator
    /// that is concentric with the enclosing toolbar capsule.
    /// - Parameters:
    ///   - isSelected: Whether the button shows its selected state.
    ///   - pillWidth: Width of the indicator pill; the height is fixed at 26pt.
    func toolbarPillFeedback(isSelected: Bool = false, pillWidth: CGFloat = 40) -> some View {
        modifier(ToolbarPillFeedbackModifier(isSelected: isSelected, pillWidth: pillWidth))
    }
}

extension Image {
    /// A symbol image pre-rendered at a fixed point size and weight.
    ///
    /// The borderless `Menu` style extracts its label's symbol image and
    /// re-renders it at the default menu size, ignoring `.font` and
    /// `.imageScale`. Pre-rendering the symbol into an `NSImage` keeps the
    /// intended size while preserving template rendering.
    init(toolbarSymbol name: String, size: CGFloat, weight: NSFont.Weight = .regular) {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) {
            self.init(nsImage: symbol)
        } else {
            self.init(systemName: name)
        }
    }
}
