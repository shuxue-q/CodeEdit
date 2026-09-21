//
//  XcodeSplitOptionsCapsule.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/17/26.
//

import SwiftUI

/// Capsule containing Split Editor and the Editor Options menu,
/// matching Xcode's `[ [+] [sliders] ]` cluster.
struct XcodeSplitOptionsCapsule: View {
    var workspace: WorkspaceDocument?
    @EnvironmentObject private var editorManager: EditorManager

    var body: some View {
        XcodeCapsuleContainer(horizontalPadding: 4) {
            HStack(spacing: 0) {
                splitEditorButton
                editorOptionsMenu
            }
        }
    }

    @ViewBuilder private var splitEditorButton: some View {
        Button {
            splitActiveEditor(edge: .trailing)
        } label: {
            Image(systemName: "plus.rectangle.on.rectangle")
                .font(.system(size: 17, weight: .regular))
                .toolbarPillFeedback()
        }
        .buttonStyle(.plain)
        .help("Split Editor Right")
    }

    @ViewBuilder private var editorOptionsMenu: some View {
        Menu {
            Button("Split Editor Right") {
                splitActiveEditor(edge: .trailing)
            }
            Button("Split Editor Down") {
                splitActiveEditor(edge: .bottom)
            }
            Divider()
            Button(editorManager.isFocusingActiveEditor ? "Exit Focused Editor" : "Focus Active Editor") {
                editorManager.toggleFocusingEditor(from: editorManager.activeEditor)
            }
        } label: {
            Image(toolbarSymbol: "slider.horizontal.below.rectangle", size: 17)
                .toolbarPillFeedback()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Editor Options")
    }

    private func splitActiveEditor(edge: Edge) {
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
