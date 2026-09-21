//
//  NavigateCommands.swift
//  CodeEdit
//
//  Created by Wouter Hennen on 13/03/2023.
//

import SwiftUI

struct NavigateCommands: Commands {

    @UpdatingWindowController var windowController: CodeEditWindowController?
    private var editor: Editor? {
        windowController?.workspace?.editorManager?.activeEditor
    }

    var body: some Commands {
        CommandMenu("Navigate") {
            Group {
                Button("Reveal in Project Navigator") {
                    NSApp.sendAction(#selector(ProjectNavigatorViewController.revealFile(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("j", modifiers: [.shift, .command])

                Button("Reveal Changes in Navigator") {

                }
                .keyboardShortcut("m", modifiers: [.shift, .command])
                .disabled(true)

                Button("Open in Next Editor") {

                }
                .keyboardShortcut(",", modifiers: [.option, .command])
                .disabled(true)

                Button("Open in...") {

                }
                .disabled(true)

                Divider()

            }
            Group {
                Button("Show Previous Tab") {
                    editor?.selectPreviousTab()
                }
                .keyboardShortcut("{", modifiers: [.command])
                .disabled(editor?.tabs.count ?? 0 <= 1)  // Disable if there's one or no tabs

                Button("Show Next Tab") {
                    editor?.selectNextTab()
                }
                .keyboardShortcut("}", modifiers: [.command])
                .disabled(editor?.tabs.count ?? 0 <= 1)  // Disable if there's one or no tabs
            }
            Group {
                Divider()

                Button("Go Forward") {
                    editor?.goForwardInHistory()
                }
                .disabled(!(editor?.canGoForwardInHistory ?? false))

                Button("Go Back") {
                    editor?.goBackInHistory()
                }
                .disabled(!(editor?.canGoBackInHistory ?? false))

                Divider()

                Button("Jump to Next Issue") {
                    jumpToIssue(next: true)
                }
                .keyboardShortcut("'", modifiers: [.control, .command])
                .disabled(windowController?.workspace == nil)

                Button("Jump to Previous Issue") {
                    jumpToIssue(next: false)
                }
                .keyboardShortcut("'", modifiers: [.control, .command, .shift])
                .disabled(windowController?.workspace == nil)
            }
            .disabled(editor == nil)
        }
    }

    private func jumpToIssue(next: Bool) {
        guard let workspace = windowController?.workspace,
              let store = ServiceContainer.resolve(.singleton, LSPService.self)?.diagnosticsStore else {
            return
        }
        if next {
            WorkspaceDiagnostics.jumpToNextIssue(workspace: workspace, store: store)
        } else {
            WorkspaceDiagnostics.jumpToPreviousIssue(workspace: workspace, store: store)
        }
    }
}
