//
//  XcodeAssistantButton.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/17/26.
//

import SwiftUI

/// Assistant button with speech bubble and plus icon, featuring Xcode's gradient stroke styling.
/// Currently opens the command palette; it is the entry point for the future AI chat.
struct XcodeAssistantButton: View {
    private let iconGradient = LinearGradient(
        colors: [
            Color.orange,
            Color.pink,
            Color.purple,
            Color.blue
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        XcodeCapsuleContainer {
            ToolbarIconButton(help: "Command Palette") {
                NSApp.sendAction(#selector(CodeEditWindowController.openCommandPalette(_:)), to: nil, from: nil)
            } icon: {
                Image(systemName: "plus.bubble")
                    .font(.system(size: ToolbarMetrics.iconSize, weight: .medium))
                    .foregroundStyle(iconGradient)
            }
        }
    }
}
