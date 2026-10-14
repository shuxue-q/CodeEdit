//
//  XcodeRunControlsCapsule.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/17/26.
//

import SwiftUI

/// Play and stop controls in one opaque capsule, matching Xcode's left-hand
/// Run/Stop segmented control: play leading, stop trailing, always visible.
struct XcodeRunControlsCapsule: View {
    @ObservedObject var taskManager: TaskManager

    /// Accessibility label of the leading segment. Matches Xcode's "Run" button.
    static let leadingControlLabel = "Run"
    /// Accessibility label of the trailing segment. Matches Xcode's "Stop" button.
    static let trailingControlLabel = "Stop"

    var body: some View {
        XcodeCapsuleContainer {
            HStack(spacing: 0) {
                StartTaskToolbarButton(taskManager: taskManager)
                ToolbarSeparator()
                StopTaskToolbarButton(taskManager: taskManager)
                if taskManager.canHotReload {
                    ToolbarSeparator()
                    HotReloadToolbarButton(taskManager: taskManager)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Run/Stop")
    }
}

/// Hot reloads the running Flutter app; ⌥-click hot restarts it. Shown only while a `flutter run`
/// task accepts hot reload.
struct HotReloadToolbarButton: View {
    @Environment(\.controlActiveState)
    private var activeState

    @ObservedObject var taskManager: TaskManager

    var body: some View {
        Button {
            taskManager.hotReload(restart: NSEvent.modifierFlags.contains(.option))
        } label: {
            Label("Hot Reload", systemImage: "bolt.fill")
                .labelStyle(.iconOnly)
                .font(.system(size: 15, weight: .regular))
                .toolbarCircleFeedback()
                .opacity(activeState == .inactive ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .help("Hot Reload (⌘\\) · Option-click to Hot Restart (⇧⌘\\)")
        .accessibilityLabel("Hot Reload")
        .accessibilityIdentifier("HotReload")
    }
}
