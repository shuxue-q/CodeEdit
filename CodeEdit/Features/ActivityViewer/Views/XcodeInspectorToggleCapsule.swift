//
//  XcodeInspectorToggleCapsule.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/17/26.
//

import SwiftUI

/// Capsule containing the Inspector toggle button replicating Xcode's `[ [sidebar.trailing] ]` control.
struct XcodeInspectorToggleCapsule: View {
    @Environment(\.window.value)
    private var window: NSWindow?

    var body: some View {
        if let windowController = window?.windowController as? CodeEditWindowController {
            InspectorToggleButton(windowController: windowController)
        } else {
            InspectorToggleButtonFallback()
        }
    }
}

private struct InspectorToggleButton: View {
    @ObservedObject var windowController: CodeEditWindowController

    var body: some View {
        inspectorCapsule(isOpen: !windowController.inspectorCollapsed) {
            windowController.toggleLastPanel()
        }
    }
}

private struct InspectorToggleButtonFallback: View {
    var body: some View {
        inspectorCapsule(isOpen: false) {
            NSApp.sendAction(#selector(CodeEditWindowController.objcToggleLastPanel), to: nil, from: nil)
        }
    }
}

private func inspectorCapsule(isOpen: Bool, action: @escaping () -> Void) -> some View {
    XcodeCapsuleContainer(horizontalPadding: 0) {
        Button(action: action) {
            Image(systemName: "sidebar.trailing")
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(isOpen ? .accentColor : .primary)
                .toolbarCircleFeedback(isSelected: isOpen)
        }
        .buttonStyle(.plain)
        .help("Hide or show the Inspector")
    }
}
