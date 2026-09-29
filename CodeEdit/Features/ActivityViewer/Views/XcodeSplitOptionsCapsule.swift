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
    @ObservedObject private var settings: Settings = .shared

    var body: some View {
        XcodeCapsuleContainer(horizontalPadding: 4) {
            HStack(spacing: 0) {
                splitEditorButton
                editorOptionsMenu
            }
        }
    }

    /// The edge the split button opens new editors on, following the Layout selection
    /// in the editor options menu.
    private var preferredSplitEdge: Edge {
        settings.preferences.general.canvasLayout == .bottom ? .bottom : .trailing
    }

    @ViewBuilder private var splitEditorButton: some View {
        Button {
            splitActiveEditor(edge: preferredSplitEdge)
        } label: {
            Image(systemName: "plus.rectangle.on.rectangle")
                .font(.system(size: 17, weight: .regular))
                .toolbarCircleFeedback()
        }
        .buttonStyle(.plain)
        .help(preferredSplitEdge == .bottom ? "Split Editor Down" : "Split Editor Right")
    }

    @ViewBuilder private var editorOptionsMenu: some View {
        Menu {
            editorOptionsContent
        } label: {
            Image(toolbarSymbol: "slider.horizontal.below.rectangle", size: 17)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .toolbarCircleFeedback()
        .help("Adjust Editor Options")
    }

    /// Xcode's editor options menu: layout and comparison modes followed by the
    /// editor display toggles and the workspace theme picker.
    @ViewBuilder private var editorOptionsContent: some View {
        Menu("Layout") {
            canvasLayoutToggle("Automatic", layout: .automatic)
            canvasLayoutToggle("Canvas on Right", layout: .right)
            canvasLayoutToggle("Canvas on Bottom", layout: .bottom)
        }
        // TODO: Enable the comparison options once a diff/comparison view exists.
        Toggle("Inline Comparison", isOn: .constant(false))
            .disabled(true)
        Toggle("Side By Side Comparison", isOn: .constant(false))
            .disabled(true)
        Divider()
        Toggle("Minimap", isOn: showMinimap)
            .keyboardShortcut("M", modifiers: [.control, .shift, .command])
        // TODO: Enable once blame/author annotations are available in the editor.
        Toggle("Authors", isOn: .constant(false))
            .keyboardShortcut("A", modifiers: [.control, .shift, .command])
            .disabled(true)
        // TODO: Enable once code coverage is available.
        Toggle("Code Coverage", isOn: .constant(false))
            .disabled(true)
        Divider()
        Toggle("Invisibles", isOn: showInvisibles)
        // TODO: Enable once the source editor supports scope guides.
        Toggle("Scope Guides", isOn: .constant(false))
            .disabled(true)
        Toggle("Wrap Lines", isOn: wrapLines)
            .keyboardShortcut("L", modifiers: [.control, .shift, .command])
        Divider()
        Button("Choose Workspace Theme…") {
            openThemeSettings()
        }
    }

    /// A radio-style toggle for the ``SettingsData/CanvasLayout`` submenu options.
    private func canvasLayoutToggle(_ title: String, layout: SettingsData.CanvasLayout) -> some View {
        Toggle(title, isOn: Binding(
            get: { settings.preferences.general.canvasLayout == layout },
            set: { _ in settings.preferences.general.canvasLayout = layout }
        ))
    }

    private var showMinimap: Binding<Bool> {
        Binding(
            get: { settings.preferences.textEditing.showMinimap },
            set: { settings.preferences.textEditing.showMinimap = $0 }
        )
    }

    private var showInvisibles: Binding<Bool> {
        Binding(
            get: { settings.preferences.textEditing.invisibleCharacters.enabled },
            set: { settings.preferences.textEditing.invisibleCharacters.enabled = $0 }
        )
    }

    /// Wrap-lines state of the active editor's file, falling back to the global setting.
    private var wrapLines: Binding<Bool> {
        Binding(
            get: {
                activeCodeFile?.wrapLines ?? settings.preferences.textEditing.wrapLinesToEditorWidth
            },
            set: { newValue in
                if let activeCodeFile {
                    activeCodeFile.wrapLines = newValue
                } else {
                    settings.preferences.textEditing.wrapLinesToEditorWidth = newValue
                }
            }
        )
    }

    private var activeCodeFile: CodeFileDocument? {
        editorManager.activeEditor.selectedTab?.file.fileDocument
    }

    /// Opens the app's Settings window on the Themes page.
    private func openThemeSettings() {
        SettingsView.pendingPage = .theme
        // The toolbar is AppKit-hosted, so `openWindow` is unavailable. Forward the
        // "Settings..." menu command (⌘,) to let the SwiftUI scene open the window.
        if let settingsItem = findSettingsMenuItem(), let action = settingsItem.action {
            NSApp.sendAction(action, to: settingsItem.target, from: settingsItem)
        }
        // Reached by an already-open Settings window; the cold case uses `pendingPage`.
        NotificationCenter.default.post(name: .openSettingsPage, object: SettingsPage.Name.theme)
    }

    private func findSettingsMenuItem() -> NSMenuItem? {
        func search(_ menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if item.keyEquivalent == ",", item.keyEquivalentModifierMask == .command {
                    return item
                }
                if let submenu = item.submenu, let match = search(submenu) {
                    return match
                }
            }
            return nil
        }
        guard let mainMenu = NSApp.mainMenu else { return nil }
        return search(mainMenu)
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
