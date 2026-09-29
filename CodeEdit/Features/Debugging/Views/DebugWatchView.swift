//
//  DebugWatchView.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/21/26.
//

import SwiftUI

/// The debugger's trailing sidebar: user-defined watch expressions and their latest
/// evaluated results. Expressions can be added with the plus button and removed via the
/// context menu.
struct DebugWatchView: View {
    @ObservedObject private var debugService: DebugService = .shared

    @State private var newExpression: String = ""
    @State private var isAddingExpression = false

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(debugService.watchExpressions, id: \.self) { expression in
                    watchRow(for: expression)
                }
            }
            .listStyle(.sidebar)

            if isAddingExpression {
                TextField("Expression", text: $newExpression)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .onSubmit(addExpression)
                    .onExitCommand {
                        newExpression = ""
                        isAddingExpression = false
                    }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PaneToolbar {
                PaneToolbarSection {
                    Button {
                        isAddingExpression.toggle()
                    } label: {
                        Image(systemName: isAddingExpression ? "minus" : "plus")
                    }
                    .buttonStyle(.icon(isActive: isAddingExpression))
                    .help(isAddingExpression ? "Cancel" : "Add Watch Expression")
                    .accessibilityIdentifier("DebugWatchAdd")
                }
            }
        }
    }

    private func watchRow(for expression: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(expression)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            if let result = debugService.watchResults[expression] {
                Text(result)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 1)
        .contextMenu {
            Button("Remove Watch Expression") {
                debugService.removeWatch(expression)
            }
        }
    }

    private func addExpression() {
        let expression = newExpression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else { return }
        debugService.addWatch(expression)
        newExpression = ""
        isAddingExpression = false
    }
}
