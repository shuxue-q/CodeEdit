//
//  NavigatorFilterView.swift
//  CodeEdit
//
//  Created by Khan Winter on 9/2/25.
//

import SwiftUI

struct NavigatorFilterView<
    MenuContents: View,
    LeadingAccessories: View,
    TrailingAccessories: View
>: View {
    @Binding var text: String
    let hasValue: Bool
    let menu: MenuContents
    let leadingAccessories: LeadingAccessories
    let trailingAccessories: TrailingAccessories

    init(
        text: Binding<String>,
        hasValue: (() -> Bool)? = nil,
        @ViewBuilder menu: () -> MenuContents,
        @ViewBuilder leadingAccessories: () -> LeadingAccessories,
        @ViewBuilder trailingAccessories: () -> TrailingAccessories
    ) {
        self._text = text
        self.hasValue = hasValue?() ?? false
        self.menu = menu()
        self.leadingAccessories = leadingAccessories()
        self.trailingAccessories = trailingAccessories()
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 5) {
                menu
                PaneTextField(
                    "Filter",
                    text: $text,
                    leadingAccessories: { leadingAccessories },
                    trailingAccessories: { trailingAccessories },
                    clearable: true,
                    hasValue: hasValue
                )
            }
            .frame(maxWidth: .infinity)
            .padding(8)
        }
    }
}
