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
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Run/Stop")
    }
}
