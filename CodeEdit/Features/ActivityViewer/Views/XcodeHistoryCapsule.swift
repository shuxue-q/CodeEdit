//
//  XcodeHistoryCapsule.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/17/26.
//

import SwiftUI

/// Capsule containing back and forward history buttons replicating Xcode's `< | >` control.
struct XcodeHistoryCapsule: View {
    @EnvironmentObject private var editorManager: EditorManager

    private var activeEditor: Editor {
        editorManager.activeEditor
    }

    private var canGoBack: Bool {
        !activeEditor.history.isEmpty && activeEditor.historyOffset < activeEditor.history.count - 1
    }

    private var canGoForward: Bool {
        activeEditor.historyOffset > 0
    }

    var body: some View {
        XcodeCapsuleContainer {
            HStack(spacing: 0) {
                backButton
                ToolbarSeparator()
                forwardButton
            }
        }
    }

    @ViewBuilder private var backButton: some View {
        ToolbarIconMenu(
            symbol: "chevron.left",
            help: "Navigate back",
            weight: .semibold,
            primaryAction: { activeEditor.goBackInHistory() },
            content: {
                ForEach(
                    Array(activeEditor.history.dropFirst(activeEditor.historyOffset + 1).enumerated()),
                    id: \.offset
                ) { index, file in
                    Button {
                        activeEditor.historyOffset += index + 1
                    } label: {
                        HStack {
                            file.icon
                            Text(file.name)
                        }
                    }
                }
            }
        )
        .disabled(!canGoBack)
        .opacity(canGoBack ? 1.0 : 0.35)
    }

    @ViewBuilder private var forwardButton: some View {
        ToolbarIconMenu(
            symbol: "chevron.right",
            help: "Navigate forward",
            weight: .semibold,
            primaryAction: { activeEditor.goForwardInHistory() },
            content: {
                ForEach(
                    Array(activeEditor.history.prefix(activeEditor.historyOffset).reversed().enumerated()),
                    id: \.offset
                ) { index, file in
                    Button {
                        activeEditor.historyOffset -= index + 1
                    } label: {
                        HStack {
                            file.icon
                            Text(file.name)
                        }
                    }
                }
            }
        )
        .disabled(!canGoForward)
        .opacity(canGoForward ? 1.0 : 0.35)
    }
}
