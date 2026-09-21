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
        XcodeCapsuleContainer(horizontalPadding: 4) {
            HStack(spacing: 0) {
                backButton
                separator
                forwardButton
            }
        }
    }

    @ViewBuilder private var backButton: some View {
        Menu {
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
        } label: {
            Image(toolbarSymbol: "chevron.left", size: 16, weight: .semibold)
                .toolbarPillFeedback()
        } primaryAction: {
            activeEditor.goBackInHistory()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(!canGoBack)
        .opacity(canGoBack ? 1.0 : 0.35)
        .buttonStyle(.plain)
        .help("Navigate back")
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(width: 0.75, height: 18)
    }

    @ViewBuilder private var forwardButton: some View {
        Menu {
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
        } label: {
            Image(toolbarSymbol: "chevron.right", size: 16, weight: .semibold)
                .toolbarPillFeedback()
        } primaryAction: {
            activeEditor.goForwardInHistory()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(!canGoForward)
        .opacity(canGoForward ? 1.0 : 0.35)
        .buttonStyle(.plain)
        .help("Navigate forward")
    }
}
