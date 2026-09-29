//
//  IconButton.swift
//  CodeEdit
//
//  Created by Khan Winter on 9/3/25.
//

import SwiftUI

extension WorkspacePanelTabBar {
    struct IconButton: View {
        let tab: Tab
        let scale: Image.Scale = .medium
        let size: CGSize

        var position: SettingsData.SidebarTabBarPosition
        var width: CGFloat?

        @Binding var selection: Tab?

        var symbolVariant: SymbolVariants {
            selection == tab ? .fill : .none
        }

        var body: some View {
            Button {
                selection = tab
            } label: {
                getSafeImage(named: tab.systemImage, accessibilityDescription: tab.title)
                    .font(.system(size: 13))
                    .symbolVariant(symbolVariant)
                    .help(tab.title)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(buttonStyle)
            .focusable(false)
            .accessibilityIdentifier("WorkspacePanelTab-\(tab.title)")
            .accessibilityLabel(tab.title)
        }

        private func getSafeImage(named: String, accessibilityDescription: String?) -> Image {
            // We still use the NSImage init to check if a symbol with the name exists.
            if NSImage(systemSymbolName: named, accessibilityDescription: nil) != nil {
                return Image(systemName: named)
            } else if let image = NSImage(named: named) {
                return Image(nsImage: image)
            } else {
                return Image(symbol: named)
            }
        }

        private var buttonStyle: IconButtonStyle {
            .icon(
                isActive: tab == selection,
                size: CGSize(
                    width: width ?? (position == .side ? 24 : 42),
                    height: position == .side ? 40 : size.height
                )
            )
        }
    }
}
