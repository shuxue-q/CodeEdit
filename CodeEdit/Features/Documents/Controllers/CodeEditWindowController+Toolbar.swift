//
//  CodeEditWindowController+Toolbar.swift
//  CodeEdit
//
//  Created by Daniel Zhu on 5/10/24.
//

import AppKit
import SwiftUI
import Combine

extension CodeEditWindowController {
    internal func setupToolbar() {
        let toolbar = NSToolbar(identifier: UUID().uuidString)
        toolbar.delegate = self
        toolbar.showsBaselineSeparator = false
        self.window?.titleVisibility = toolbarCollapsed ? .visible : .hidden
        self.window?.toolbarStyle = .unified
        // Custom items draw their own views. `.labelOnly` still reserves a label
        // row under them, which leaves a gap between this row and the jump bar.
        toolbar.displayMode = .iconOnly
        self.window?.titlebarSeparatorStyle = .automatic
        self.window?.toolbar = toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // Run controls share the navigator section with the sidebar toggle but are
        // pushed against the tracking separator by a flexible space, so they sit at
        // the trailing edge of the navigator area.
        [
            .toggleFirstSidebarItem,
            .flexibleSpace,
            .runControlsItem,
            .sidebarTrackingSeparator,
            .activityViewerLeading,
            .flexibleSpace,
            .activityViewer,
            .flexibleSpace,
            .activityViewerTrailing,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleFirstSidebarItem,
            .sidebarTrackingSeparator,
            .flexibleSpace,
            .itemListTrackingSeparator,
            .toggleLastSidebarItem,
            .branchPicker,
            .activityViewer,
            .activityViewerLeading,
            .activityViewerTrailing,
            .notificationItem,
            .startTaskSidebarItem,
            .stopTaskSidebarItem,
            .runControlsItem,
        ]
    }

    func toggleToolbar() {
        toolbarCollapsed.toggle()
        workspace?.addToWorkspaceState(key: .toolbarCollapsed, value: toolbarCollapsed)
        updateToolbarVisibility()
    }

    func updateToolbarVisibility() {
        if toolbarCollapsed {
            window?.titleVisibility = .visible
            window?.title = workspace?.workspaceFileManager?.folderUrl.lastPathComponent ?? "Empty"
            window?.toolbar = nil
        } else {
            window?.titleVisibility = .hidden
            setupToolbar()
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .itemListTrackingSeparator:
            guard let splitViewController else { return nil }

            return NSTrackingSeparatorToolbarItem(
                identifier: .itemListTrackingSeparator,
                splitView: splitViewController.splitView,
                dividerIndex: 1
            )
        case .toggleFirstSidebarItem:
            return navigatorToggleItem()
        case .toggleLastSidebarItem:
            let toolbarItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier.toggleLastSidebarItem)
            toolbarItem.paletteLabel = "Inspector Sidebar"
            toolbarItem.toolTip = "Hide or show the Inspectors"
            toolbarItem.isBordered = false
            toolbarItem.target = self
            toolbarItem.action = #selector(self.objcToggleLastPanel)
            toolbarItem.image = NSImage(
                systemSymbolName: "sidebar.trailing",
                accessibilityDescription: nil
            )?.withSymbolConfiguration(.init(scale: .large))

            return toolbarItem
        case .stopTaskSidebarItem:
            return stopTaskSidebarItem()
        case .startTaskSidebarItem:
            return startTaskSidebarItem()
        case .runControlsItem:
            return runControlsItem()
        case .branchPicker:
            let toolbarItem = NSToolbarItem(itemIdentifier: .branchPicker)
            let view = NSHostingView(
                rootView: ToolbarBranchPicker(
                    workspaceFileManager: workspace?.workspaceFileManager
                )
            )
            toolbarItem.view = view
            toolbarItem.isBordered = false
            return toolbarItem
        case .activityViewer:
            return activityViewerItem()
        case .activityViewerLeading:
            return activityViewerLeadingItem()
        case .activityViewerTrailing:
            return activityViewerTrailingItem()
        case .notificationItem:
            return notificationItem()
        default:
            return NSToolbarItem(itemIdentifier: itemIdentifier)
        }
    }

    /// The navigator toggle, drawn by the same SwiftUI capsule as the inspector toggle.
    private func navigatorToggleItem() -> NSToolbarItem {
        let toolbarItem = NSToolbarItem(itemIdentifier: .toggleFirstSidebarItem)
        toolbarItem.paletteLabel = " Navigator Sidebar"
        toolbarItem.toolTip = "Hide or show the Navigator"
        toolbarItem.view = NSHostingView(
            rootView: XcodeNavigatorToggleCapsule()
                .environment(\.window, WindowBox(value: window))
        )
        toolbarItem.isBordered = false
        return toolbarItem
    }

    private func stopTaskSidebarItem() -> NSToolbarItem? {
        let toolbarItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier.stopTaskSidebarItem)

        guard let taskManager = workspace?.taskManager else { return nil }

        let view = NSHostingView(
            rootView: StopTaskToolbarButton(taskManager: taskManager)
        )
        toolbarItem.view = view
        toolbarItem.isBordered = false

        return toolbarItem
    }

    private func startTaskSidebarItem() -> NSToolbarItem? {
        let toolbarItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier.startTaskSidebarItem)

        guard let taskManager = workspace?.taskManager else { return nil }
        guard let workspace = workspace else { return nil }

        let view = NSHostingView(
            rootView: StartTaskToolbarButton(taskManager: taskManager)
                .environmentObject(workspace)
        )
        toolbarItem.view = view
        toolbarItem.isBordered = false

        return toolbarItem
    }

    private func runControlsItem() -> NSToolbarItem? {
        let toolbarItem = NSToolbarItem(itemIdentifier: .runControlsItem)
        guard let taskManager = workspace?.taskManager, let workspace else { return nil }

        let view = NSHostingView(
            rootView: XcodeRunControlsCapsule(taskManager: taskManager)
                .environmentObject(workspace)
                .environment(\.window, WindowBox(value: window))
        )
        toolbarItem.view = view
        toolbarItem.isBordered = false
        // Keep run controls out of the overflow menu: the activity viewer groups
        // carry the default priority and are pushed into overflow first instead.
        toolbarItem.visibilityPriority = .user
        toolbarItem.paletteLabel = "Run/Stop"
        toolbarItem.toolTip = "Start or stop the selected task"

        return toolbarItem
    }

    private func notificationItem() -> NSToolbarItem? {
        let toolbarItem = NSToolbarItem(itemIdentifier: .notificationItem)
        guard let workspace = workspace else { return nil }
        let view = NSHostingView(rootView: NotificationToolbarItem().environmentObject(workspace))
        toolbarItem.view = view
        toolbarItem.isBordered = false
        return toolbarItem
    }

    private func activityViewerItem() -> NSToolbarItem? {
        let toolbarItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier.activityViewer)
        toolbarItem.visibilityPriority = .user
        guard let workspaceSettingsManager = workspace?.workspaceSettingsManager,
              let taskManager = workspace?.taskManager
        else { return nil }

        let activityViewer = ActivityViewer(
            workspaceFileManager: workspace?.workspaceFileManager,
            workspaceSettingsManager: workspaceSettingsManager,
            taskManager: taskManager,
            workspace: workspace
        )

        toolbarItem.view = activityViewerHostingView(for: activityViewer)
        toolbarItem.isBordered = false
        return toolbarItem
    }

    private func activityViewerLeadingItem() -> NSToolbarItem? {
        let toolbarItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier.activityViewerLeading)
        guard let workspaceSettingsManager = workspace?.workspaceSettingsManager,
              let taskNotificationHandler = workspace?.taskNotificationHandler,
              let taskManager = workspace?.taskManager
        else { return nil }

        let activityViewerLeading = ActivityViewerLeading(
            workspaceFileManager: workspace?.workspaceFileManager,
            taskNotificationHandler: taskNotificationHandler,
            workspaceSettingsManager: workspaceSettingsManager,
            taskManager: taskManager,
            workspace: workspace
        )

        toolbarItem.view = activityViewerHostingView(for: activityViewerLeading)
        toolbarItem.isBordered = false
        return toolbarItem
    }

    private func activityViewerTrailingItem() -> NSToolbarItem? {
        let toolbarItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier.activityViewerTrailing)
        toolbarItem.view = activityViewerHostingView(for: ActivityViewerTrailing(workspace: workspace))
        toolbarItem.isBordered = false
        return toolbarItem
    }

    /// Wraps a toolbar SwiftUI view in a hosting view with the workspace and editor
    /// environment objects that are available injected, matching the activity viewer's
    /// previous single-item environment setup.
    private func activityViewerHostingView<Content: View>(for content: Content) -> NSHostingView<AnyView> {
        let rootView: AnyView
        let windowBox = WindowBox(value: window)
        if let workspace = workspace, let editorManager = workspace.editorManager {
            rootView = AnyView(
                content
                    .environmentObject(workspace)
                    .environmentObject(editorManager)
                    .themedChromeText()
                    .environment(\.window, windowBox)
            )
        } else if let workspace = workspace {
            rootView = AnyView(
                content
                    .environmentObject(workspace)
                    .themedChromeText()
                    .environment(\.window, windowBox)
            )
        } else {
            rootView = AnyView(content.themedChromeText().environment(\.window, windowBox))
        }

        return NSHostingView(rootView: rootView)
    }
}
