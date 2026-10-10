//
//  XcodeLayoutModesCapsule.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/17/26.
//

import SwiftUI
import Combine

/// Capsule containing Standard, Assistant Editor, and Code Review modes.
/// Replicates Xcode's `[ [editors] [assistant] | [review] ]` control, where the
/// active mode is highlighted with a gray rounded background.
struct XcodeLayoutModesCapsule: View {
    var workspace: WorkspaceDocument?
    @EnvironmentObject private var editorManager: EditorManager
    @ObservedObject private var settings: Settings = .shared
    @Environment(\.window.value)
    private var window: NSWindow?

    /// Whether the Source Control navigator is showing. Fed by the window controller's publisher
    /// rather than read from `NSApp.keyWindow` during `body`, which tracked nothing and ran every render.
    @State private var isCodeReviewActive: Bool = false

    private var windowController: CodeEditWindowController? {
        window?.windowController as? CodeEditWindowController
    }

    private var isMultiEditor: Bool {
        editorManager.flattenedEditors.count > 1
    }

    private var isAssistantActive: Bool {
        isMultiEditor && !editorManager.isFocusingActiveEditor
    }

    private var isStandardActive: Bool {
        !isAssistantActive && !isCodeReviewActive
    }

    var body: some View {
        XcodeCapsuleContainer {
            HStack(spacing: 3) {
                standardEditorButton
                assistantEditorButton
                ToolbarSeparator()
                codeReviewButton
            }
        }
        .onReceive(windowController?.codeReviewActivePublisher ?? Just(false).eraseToAnyPublisher()) {
            isCodeReviewActive = $0
        }
    }

    @ViewBuilder private var standardEditorButton: some View {
        ToolbarIconButton(symbol: "square.stack", help: "Standard Editor", isSelected: isStandardActive) {
            selectStandardEditor()
        }
    }

    @ViewBuilder private var assistantEditorButton: some View {
        ToolbarIconButton(help: "Assistant Editor", isSelected: isAssistantActive) {
            selectAssistantEditor()
        } icon: {
            assistantIcon
        }
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

    @ViewBuilder private var codeReviewButton: some View {
        ToolbarIconButton(
            symbol: "arrow.left.arrow.right",
            help: "Code Review (Source Control)",
            isSelected: isCodeReviewActive
        ) {
            selectCodeReview()
        }
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
        guard let windowController else {
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

    /// The edge new auxiliary editors open on, following the Layout menu selection.
    private var preferredAuxiliaryEdge: Edge {
        settings.preferences.general.canvasLayout == .bottom ? .bottom : .trailing
    }

    private func splitActiveEditor() {
        guard let workspace else { return }
        let edge = preferredAuxiliaryEdge
        let activeEditor = editorManager.activeEditor
        let newEditor: Editor
        if let tab = activeEditor.selectedTab {
            newEditor = .init(files: [tab], temporaryTab: tab, workspace: workspace)
        } else {
            newEditor = .init()
        }

        if let parent = activeEditor.parent {
            let index = parent.editorLayouts.firstIndex(of: .one(activeEditor)) ?? 0
            parent.split(edge, at: index, new: newEditor)
        } else {
            switch editorManager.editorLayout {
            case .horizontal(let data):
                let index = data.editorLayouts.firstIndex(of: .one(activeEditor)) ?? 0
                data.split(edge, at: index, new: newEditor)
            case .vertical(let data):
                let index = data.editorLayouts.firstIndex(of: .one(activeEditor)) ?? 0
                data.split(edge, at: index, new: newEditor)
            case .one:
                let oldLayout = editorManager.editorLayout
                let axis: Axis = edge == .bottom || edge == .top ? .vertical : .horizontal
                let data = SplitViewData(axis, editorLayouts: [oldLayout])
                data.split(edge, at: 0, new: newEditor)
                editorManager.editorLayout = axis == .vertical ? .vertical(data) : .horizontal(data)
            }
        }
        editorManager.updateCachedFlattenedEditors = true
        editorManager.activeEditor = newEditor
    }
}
