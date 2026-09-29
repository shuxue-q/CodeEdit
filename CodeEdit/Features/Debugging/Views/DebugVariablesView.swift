//
//  DebugVariablesView.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/21/26.
//

import SwiftUI

/// Loads the variables tree shown in ``DebugVariablesView``.
///
/// Scopes are fetched for the currently selected stack frame; each scope's variables (and
/// the children of structured variables) are fetched lazily as nodes are expanded.
@MainActor
final class DebugVariablesViewModel: ObservableObject {
    /// The root nodes of the tree — one per scope of the selected frame.
    @Published private(set) var roots: [DebugVariableNode] = []

    private let debugService: DebugService

    init(debugService: DebugService) {
        self.debugService = debugService
    }

    convenience init() {
        self.init(debugService: .shared)
    }

    /// Reloads the scopes (and their top-level variables) for a stack frame.
    /// - Parameter frameID: The frame to load scopes for, or `nil` to clear the tree.
    func loadScopes(frameID: Int?) async {
        guard let frameID else {
            roots = []
            return
        }
        do {
            let scopes = try await debugService.fetchScopes(frameID: frameID)
            roots = scopes.map(DebugVariableNode.init(scope:))
        } catch {
            roots = []
        }
    }

    /// Loads the children of an expandable node, if they have not been loaded yet.
    /// - Parameter node: The node to expand.
    func loadChildren(of node: DebugVariableNode) async {
        guard node.variablesReference > 0, node.children == nil else { return }
        do {
            let variables = try await debugService.fetchVariables(reference: node.variablesReference)
            node.children = variables.map(DebugVariableNode.init(variable:))
        } catch {
            node.children = []
        }
    }
}

/// The debugger panel's main area: an expandable tree of scopes and variables for the
/// selected stack frame, with a collapsible debug console section below it.
struct DebugVariablesView: View {
    @ObservedObject private var debugService: DebugService = .shared
    @StateObject private var viewModel = DebugVariablesViewModel()

    /// Reload trigger combining the selected frame and the session state, so the tree
    /// refreshes each time the debuggee pauses, even on the same frame.
    private struct RefreshKey: Equatable {
        let frameID: Int?
        let state: DebugService.SessionState
    }

    var body: some View {
        Group {
            if debugService.sessionState == .inactive {
                CEContentUnavailableView(
                    "Not Debugging",
                    description: "Start a debug session to inspect variables."
                )
            } else {
                debugContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: RefreshKey(frameID: debugService.selectedFrameID, state: debugService.sessionState)) {
            guard debugService.sessionState == .paused else {
                if debugService.sessionState == .inactive {
                    await viewModel.loadScopes(frameID: nil)
                }
                return
            }
            await viewModel.loadScopes(frameID: debugService.selectedFrameID)
        }
    }

    private var debugContent: some View {
        VStack(spacing: 0) {
            variablesList
            DebugConsoleSection()
        }
    }

    private var variablesList: some View {
        Group {
            if viewModel.roots.isEmpty {
                Text(debugService.sessionState == .paused ? "No variables." : "Running.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.roots) { node in
                        DebugVariableNodeView(node: node, viewModel: viewModel)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A single row (and, for expandable variables, the subtree) of the variables tree.
struct DebugVariableNodeView: View {
    @ObservedObject var node: DebugVariableNode
    @ObservedObject var viewModel: DebugVariablesViewModel

    @State private var isExpanded = false

    var body: some View {
        if node.variablesReference > 0 {
            DisclosureGroup(isExpanded: $isExpanded) {
                if let children = node.children {
                    ForEach(children) { child in
                        DebugVariableNodeView(node: child, viewModel: viewModel)
                    }
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            } label: {
                label
            }
            .onChange(of: isExpanded) { _, expanded in
                guard expanded else { return }
                Task {
                    await viewModel.loadChildren(of: node)
                }
            }
        } else {
            label
        }
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(node.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            if !node.value.isEmpty {
                Text(node.value)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if let type = node.type {
                Text(type)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}

/// The collapsible debug console shown below the variables tree, newest entries at the bottom.
struct DebugConsoleSection: View {
    @ObservedObject private var debugService: DebugService = .shared

    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(debugService.consoleEntries) { entry in
                            Text(entry.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(entry.id)
                        }
                    }
                    .padding(6)
                }
                .frame(minHeight: 40, maxHeight: 160)
                .onChange(of: debugService.consoleEntries.count) { _, _ in
                    guard let lastID = debugService.consoleEntries.last?.id else { return }
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        } label: {
            Text("Console")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
