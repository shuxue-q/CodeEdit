//
//  PopoverContainer.swift
//  CodeEdit
//
//  Created by Khan Winter on 8/29/25.
//

import SwiftUI

/// Container for SwiftUI views presented in a popover.
struct PopoverContainer<ContentView: View>: View {
    let content: () -> ContentView

    init(@ViewBuilder content: @escaping () -> ContentView) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .font(.subheadline)
        .padding(5)
        .frame(minWidth: 215)
    }
}
