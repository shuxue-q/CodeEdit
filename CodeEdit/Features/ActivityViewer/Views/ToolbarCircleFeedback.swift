//
//  ToolbarCircleFeedback.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/20/26.
//

import SwiftUI

/// Circular hover and selection feedback for toolbar icon buttons inside an
/// ``XcodeCapsuleContainer``, matching Xcode's toolbar. The circle's diameter is
/// twice the icon size and it is centered in the icon's 37pt-wide, 40pt-tall
/// cell, its center coinciding with the enclosing 40pt-tall capsule's center.
private struct ToolbarCircleFeedbackModifier: ViewModifier {
    /// Whether the button is in a selected (active) state.
    var isSelected: Bool
    /// Point size of the toolbar icon. The feedback circle's diameter is twice this value.
    var iconSize: CGFloat = 17

    @Environment(\.isEnabled)
    private var isEnabled

    @State private var isHovered: Bool = false

    func body(content: Content) -> some View {
        content
            .frame(width: 37, height: 40)
            .background {
                Circle()
                    .fill(fillColor)
                    .frame(width: iconSize * 2, height: iconSize * 2)
                    .opacity(showsCircle ? 1 : 0)
            }
            .contentShape(Circle())
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: showsCircle)
    }

    private var showsCircle: Bool {
        isSelected || (isHovered && isEnabled)
    }

    private var fillColor: Color {
        Color.primary.opacity(isSelected ? 0.14 : 0.08)
    }
}

extension View {
    /// Gives a toolbar icon button a circular hover/selection indicator
    /// that is concentric with the enclosing toolbar capsule.
    /// - Parameters:
    ///   - isSelected: Whether the button shows its selected state.
    ///   - iconSize: Point size of the icon; the indicator circle's diameter is twice this value.
    func toolbarCircleFeedback(isSelected: Bool = false, iconSize: CGFloat = 17) -> some View {
        modifier(ToolbarCircleFeedbackModifier(isSelected: isSelected, iconSize: iconSize))
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
