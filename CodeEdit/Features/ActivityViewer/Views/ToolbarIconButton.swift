//
//  ToolbarIconButton.swift
//  CodeEdit
//
//  Created by CodeEdit on 10/10/26.
//

import SwiftUI

/// A toolbar icon button: a regular-weight icon in a fixed cell with circular hover and
/// selection feedback, sized by ``ToolbarMetrics``.
struct ToolbarIconButton<Icon: View>: View {
    let help: String
    var isSelected: Bool = false
    var tint: Color?
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            icon()
                .foregroundColor(tint ?? .primary)
                .toolbarCircleFeedback(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .help(help.localizedAtRuntime)
    }
}

extension ToolbarIconButton where Icon == Image {
    /// Creates a button showing an SF Symbol at the standard toolbar icon size.
    init(
        symbol: String,
        help: String,
        isSelected: Bool = false,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.init(help: help, isSelected: isSelected, tint: tint, action: action) {
            Image(toolbarSymbol: symbol, size: ToolbarMetrics.iconSize)
        }
    }
}

/// A toolbar icon menu using the same cell and feedback as ``ToolbarIconButton``.
/// With a `primaryAction`, a plain click runs it and the menu opens on press-and-hold.
struct ToolbarIconMenu<MenuContent: View>: View {
    let symbol: String
    let help: String
    var weight: NSFont.Weight = .regular
    var primaryAction: (() -> Void)?
    @ViewBuilder let content: () -> MenuContent

    var body: some View {
        menu
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .toolbarCircleFeedback()
            .buttonStyle(.plain)
            .help(help.localizedAtRuntime)
    }

    @ViewBuilder private var menu: some View {
        if let primaryAction {
            Menu(content: content, label: label, primaryAction: primaryAction)
        } else {
            Menu(content: content, label: label)
        }
    }

    private func label() -> some View {
        Image(toolbarSymbol: symbol, size: ToolbarMetrics.iconSize, weight: weight)
    }
}
