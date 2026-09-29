//
//  EditorCommands.swift
//  CodeEdit
//
//  Created by Bogdan Belogurov on 21/05/2025.
//

import SwiftUI
import CodeEditKit

struct EditorCommands: Commands {

    @UpdatingWindowController var windowController: CodeEditWindowController?
    private var editor: Editor? {
        windowController?.workspace?.editorManager?.activeEditor
    }

    var body: some Commands {
        CommandMenu("Editor") {
            Menu("Structure") {
                Button("Move line up") {
                    editor?.selectedTab?.rangeTranslator.moveLinesUp()
                }
                .keyboardShortcut("[", modifiers: [.command, .option])

                Button("Move line down") {
                    editor?.selectedTab?.rangeTranslator.moveLinesDown()
                }
                .keyboardShortcut("]", modifiers: [.command, .option])
            }

            Button("Format Code") {
                editor?.selectedTab?.rangeTranslator.formatCode()
            }
            .keyboardShortcut("i", modifiers: [.control])
            .disabled(!canFormatActiveFile)

            Divider()

            Button("Show Markdown Source") {
                editor?.selectedTab?.markdownPreview.mode = .source
            }
            .disabled(!activeFileIsMarkdown)

            Button("Show Markdown Preview") {
                editor?.selectedTab?.markdownPreview.mode = .preview
            }
            .disabled(!activeFileIsMarkdown)

            Button("Show Markdown Source and Preview") {
                editor?.selectedTab?.markdownPreview.mode = .split
            }
            .disabled(!activeFileIsMarkdown)
        }
    }

    private var activeFileIsMarkdown: Bool {
        guard let tab = editor?.selectedTab else { return false }
        if let document = tab.file.fileDocument {
            return MarkdownPreview.isMarkdown(document)
        }
        return MarkdownPreview.isMarkdownURL(tab.file.url)
    }

    /// Format Code applies to languages clang-format understands, such as C and C++.
    private var canFormatActiveFile: Bool {
        guard let url = editor?.selectedTab?.file.url else { return false }
        return ClangFormatLanguage.supports(url: url)
    }
}
