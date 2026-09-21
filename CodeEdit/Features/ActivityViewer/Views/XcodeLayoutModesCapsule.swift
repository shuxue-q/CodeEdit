//
//  XcodeLayoutModesCapsule.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/17/26.
//

import SwiftUI

/// Capsule containing Standard, Assistant Editor, and Code Review modes.
/// Replicates Xcode's `[ [editors] [assistant] | [review] ]` control, where the
/// active mode is highlighted with a gray rounded background.
struct XcodeLayoutModesCapsule: View {
    var workspace: WorkspaceDocument?
    @EnvironmentObject private var editorManager: EditorManager

    private var isMultiEditor: Bool {
        editorManager.flattenedEditors.count > 1
    }

    private var isAssistantActive: Bool {
        isMultiEditor && !editorManager.isFocusingActiveEditor
    }

    private var isCodeReviewActive: Bool {
        guard let windowController = NSApp.keyWindow?.windowController as? CodeEditWindowController else {
            return false
        }
        return windowController.navigatorSidebarViewModel?.selectedTab == .sourceControl
            && !windowController.navigatorCollapsed
    }

    private var isStandardActive: Bool {
        !isAssistantActive && !isCodeReviewActive
    }

    var body: some View {
        XcodeCapsuleContainer(horizontalPadding: 4) {
            HStack(spacing: 3) {
                standardEditorButton
                assistantEditorButton
                separator
                codeReviewButton
            }
        }
    }

    @ViewBuilder private var standardEditorButton: some View {
        Button {
            selectStandardEditor()
        } label: {
            Image(systemName: "square.stack")
                .font(.system(size: 17, weight: .regular))
                .modifier(LayoutModeIconModifier(isActive: isStandardActive))
        }
        .buttonStyle(.plain)
        .help("Standard Editor")
    }

    @ViewBuilder private var assistantEditorButton: some View {
        Button {
            selectAssistantEditor()
        } label: {
            assistantIcon
                .modifier(LayoutModeIconModifier(isActive: isAssistantActive))
        }
        .buttonStyle(.plain)
        .help("Assistant Editor")
    }

    private var assistantIcon: some View {
        ZStack {
            Circle()
                .strokeBorder(lineWidth: 1.5)
                .frame(width: 13, height: 13)
                .offset(x: -4.2)

            Circle()
                .strokeBorder(lineWidth: 1.5)
                .frame(width: 13, height: 13)
                .offset(x: 4.2)
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(width: 0.75, height: 16)
    }

    @ViewBuilder private var codeReviewButton: some View {
        Button {
            selectCodeReview()
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 16, weight: .regular))
                .modifier(LayoutModeIconModifier(isActive: isCodeReviewActive))
        }
        .buttonStyle(.plain)
        .help("Code Review (Source Control)")
    }

    private func selectStandardEditor() {
        if isCodeReviewActive {
            selectCodeReview()
        }
        if isAssistantActive {
            editorManager.toggleFocusingEditor(from: editorManager.activeEditor)
        }
    }

    private func selectAssistantEditor() {
        if editorManager.isFocusingActiveEditor {
            editorManager.isFocusingActiveEditor = false
        } else if editorManager.flattenedEditors.count <= 1 {
            splitActiveEditor()
        } else {
            let other = editorManager.findSomeEditor(excluding: editorManager.activeEditor)
            editorManager.activeEditor = other
        }
    }

    private func selectCodeReview() {
        guard let windowController = NSApp.keyWindow?.windowController as? CodeEditWindowController else {
            NSApp.sendAction(#selector(CodeEditWindowController.objcToggleFirstPanel), to: nil, from: nil)
            return
        }
        if isCodeReviewActive {
            windowController.toggleFirstPanel()
        } else {
            windowController.navigatorSidebarViewModel?.selectedTab = .sourceControl
            if windowController.navigatorCollapsed {
                windowController.toggleFirstPanel()
            }
        }
    }

    private func splitActiveEditor() {
        guard let workspace else { return }
        let activeEditor = editorManager.activeEditor
        let newEditor: Editor
        if let tab = activeEditor.selectedTab {
            newEditor = .init(files: [tab], temporaryTab: tab, workspace: workspace)
        } else {
            newEditor = .init()
        }

        if let parent = activeEditor.parent {
            let index = parent.editorLayouts.firstIndex(of: .one(activeEditor)) ?? 0
            parent.split(.trailing, at: index, new: newEditor)
        } else {
            switch editorManager.editorLayout {
            case .horizontal(let data):
                let index = data.editorLayouts.firstIndex(of: .one(activeEditor)) ?? 0
                data.split(.trailing, at: index, new: newEditor)
            case .vertical(let data):
                let index = data.editorLayouts.firstIndex(of: .one(activeEditor)) ?? 0
                data.split(.trailing, at: index, new: newEditor)
            case .one:
                let oldLayout = editorManager.editorLayout
                let data = SplitViewData(.horizontal, editorLayouts: [oldLayout])
                data.split(.trailing, at: 0, new: newEditor)
                editorManager.editorLayout = .horizontal(data)
            }
        }
        editorManager.updateCachedFlattenedEditors = true
        editorManager.activeEditor = newEditor
    }
}

/// Sizes a layout-mode icon and draws the capsule-shaped highlight for the active mode.
private struct LayoutModeIconModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .foregroundColor(.primary)
            .toolbarPillFeedback(isSelected: isActive)
    }
}
