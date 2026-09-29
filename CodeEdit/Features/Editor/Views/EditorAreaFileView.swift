//
//  EditorAreaFileView.swift
//  CodeEdit
//
//  Created by Pavel Kasila on 20.03.22.
//

import AppKit
import AVKit
import CodeEditSourceEditor
import SwiftUI

struct EditorAreaFileView: View {

    @EnvironmentObject private var editorManager: EditorManager
    @EnvironmentObject private var editor: Editor
    @EnvironmentObject private var statusBarViewModel: StatusBarViewModel

    @Environment(\.edgeInsets)
    private var edgeInsets

    var editorInstance: EditorInstance
    var codeFile: CodeFileDocument
    @ObservedObject private var markdownPreview: MarkdownPreviewModel

    init(editorInstance: EditorInstance, codeFile: CodeFileDocument) {
        self.editorInstance = editorInstance
        self.codeFile = codeFile
        self._markdownPreview = ObservedObject(wrappedValue: editorInstance.markdownPreview)
    }

    @ViewBuilder var editorAreaFileView: some View {
        if MarkdownPreview.isMarkdown(codeFile) {
            MarkdownDocumentView(
                editorInstance: editorInstance,
                codeFile: codeFile,
                mode: markdownPreview.mode
            )
        } else if let utType = codeFile.utType, utType.conforms(to: .text) {
            CodeFileView(
                editorInstance: editorInstance,
                codeFile: codeFile
            )
        } else {
            NonTextFileView(fileDocument: codeFile)
                .padding(.top, edgeInsets.top - 1.74)
                .padding(.bottom, StatusBarView.height + 1.26)
                .modifier(UpdateStatusBarInfo(with: codeFile.fileURL))
                .onDisappear {
                    statusBarViewModel.dimensions = nil
                    statusBarViewModel.fileSize = nil
                }
        }
    }

    var body: some View {
        editorAreaFileView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onHover(perform: updateCursor)
    }

    private func updateCursor(_ hovering: Bool) {
        let showTextCursor = !MarkdownPreview.isMarkdown(codeFile) || markdownPreview.mode != .preview
        guard showTextCursor else { return }
        DispatchQueue.main.async {
            if hovering {
                NSCursor.iBeam.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
