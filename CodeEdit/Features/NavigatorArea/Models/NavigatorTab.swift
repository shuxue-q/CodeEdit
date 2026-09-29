//
//  NavigatorTab.swift
//  CodeEdit
//
//  Created by Wouter Hennen on 02/06/2023.
//

import SwiftUI
import CodeEditKit
import ExtensionFoundation

enum NavigatorTab: WorkspacePanelTab {
    case project
    case sourceControl
    case bookmarks
    case search
    case issues
    case tests
    case debug
    case breakpoints
    case reports
    case uiExtension(endpoint: AppExtensionIdentity, data: ResolvedSidebar.SidebarStore)

    var systemImage: String {
        switch self {
        case .project:
            return "folder"
        case .sourceControl:
            return "vault"
        case .bookmarks:
            return "bookmark"
        case .search:
            return "magnifyingglass"
        case .issues:
            return "exclamationmark.triangle"
        case .tests:
            return "diamond"
        case .debug:
            return "debugnavigator"
        case .breakpoints:
            return "breakpoint"
        case .reports:
            return "doc.plaintext"
        case .uiExtension(_, let data):
            return data.icon ?? "e.square"
        }
    }

    var id: String {
        if case let .uiExtension(endpoint, data) = self {
            return endpoint.bundleIdentifier + data.sceneID
        }
        return title
    }

    var title: String {
        switch self {
        case .project:
            return "Project"
        case .sourceControl:
            return "Source Control"
        case .bookmarks:
            return "Bookmarks"
        case .search:
            return "Search"
        case .issues:
            return "Issues"
        case .tests:
            return "Tests"
        case .debug:
            return "Debug"
        case .breakpoints:
            return "Breakpoints"
        case .reports:
            return "Reports"
        case .uiExtension(_, let data):
            return data.help ?? data.sceneID
        }
    }

    var body: some View {
        switch self {
        case .project:
            ProjectNavigatorView()
        case .sourceControl:
            SourceControlNavigatorView()
        case .bookmarks:
            BookmarkNavigatorView()
        case .search:
            FindNavigatorView()
        case .issues:
            IssuesNavigatorView()
        case .tests:
            TestsNavigatorView()
        case .debug:
            DebugNavigatorView()
        case .breakpoints:
            BreakpointsNavigatorView()
        case .reports:
            ReportsNavigatorView()
        case let .uiExtension(endpoint, data):
            ExtensionSceneView(with: endpoint, sceneID: data.sceneID)
        }
    }

    @ViewBuilder
    func bottomView(workspace: WorkspaceDocument) -> some View {
        switch self {
        case .project:
            ProjectNavigatorToolbarBottom()
        case .sourceControl:
            if let sourceControlManager = workspace.sourceControlManager {
                SourceControlNavigatorToolbarBottom()
                    .environmentObject(sourceControlManager)
            }
        case .search:
            FindNavigatorToolbarBottom()
        case .debug:
            DebugNavigatorToolbarBottom()
        case .bookmarks, .issues, .tests, .breakpoints, .reports, .uiExtension:
            EmptyView()
        }
    }
}
