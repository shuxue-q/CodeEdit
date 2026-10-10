//
//  XcodeNavigatorToggleCapsule.swift
//  CodeEdit
//
//  Created by CodeEdit on 10/10/26.
//

import SwiftUI

/// Capsule containing the Navigator toggle button, the mirror image of
/// ``XcodeInspectorToggleCapsule``. The icon takes the accent color while the navigator is open.
struct XcodeNavigatorToggleCapsule: View {
    @Environment(\.window.value)
    private var window: NSWindow?

    var body: some View {
        if let windowController = window?.windowController as? CodeEditWindowController {
            NavigatorToggleButton(windowController: windowController)
        } else {
            sidebarToggleCapsule(
                symbol: "sidebar.leading",
                help: "Hide or show the Navigator",
                isOpen: false
            ) {
                NSApp.sendAction(#selector(CodeEditWindowController.objcToggleFirstPanel), to: nil, from: nil)
            }
        }
    }
}

private struct NavigatorToggleButton: View {
    let windowController: CodeEditWindowController
    /// Mirrors `navigatorCollapsed` only, so other published changes on the controller
    /// do not re-render the capsule while the navigator animates.
    @State private var isCollapsed: Bool

    init(windowController: CodeEditWindowController) {
        self.windowController = windowController
        _isCollapsed = State(initialValue: windowController.navigatorCollapsed)
    }

    var body: some View {
        sidebarToggleCapsule(
            symbol: "sidebar.leading",
            help: "Hide or show the Navigator",
            isOpen: !isCollapsed
        ) {
            windowController.toggleFirstPanel()
        }
        .onReceive(windowController.$navigatorCollapsed.removeDuplicates()) { isCollapsed = $0 }
    }
}

/// A capsule with a single sidebar toggle button, shared by the navigator and inspector toggles.
func sidebarToggleCapsule(
    symbol: String,
    help: String,
    isOpen: Bool,
    action: @escaping () -> Void
) -> some View {
    XcodeCapsuleContainer {
        ToolbarIconButton(
            symbol: symbol,
            help: help,
            isSelected: isOpen,
            tint: isOpen ? .accentColor : nil,
            action: action
        )
    }
}
