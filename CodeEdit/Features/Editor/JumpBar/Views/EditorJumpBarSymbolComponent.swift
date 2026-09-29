//
//  EditorJumpBarSymbolComponent.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/17/26.
//

import SwiftUI
import LanguageServerProtocol
import CodeEditSourceEditor

/// Symbol crumbs after the file path. The last crumb is the variable under the cursor when there is one,
/// and the crumb before that is the enclosing function.
struct EditorJumpBarSymbolComponent: View {
    @ObservedObject var model: EditorJumpBarSymbolModel
    @ObservedObject var editorInstance: EditorInstance

    @ObservedObject private var themeModel: ThemeModel = .shared

    @Environment(\.controlActiveState)
    private var activeState

    @Environment(\.isActiveEditor)
    private var isActiveEditor

    var body: some View {
        HStack(spacing: 0) {
            ForEach(model.pathSegments) { segment in
                JumpBarPathCrumb(segment: segment, labelColor: labelColor) { item in
                    select(item)
                }
            }
        }
        .onAppear {
            model.cursorMoved(editorInstance.cursorPositions.first)
        }
        .onChange(of: editorInstance.cursorPositions) { _, newValue in
            model.cursorMoved(newValue.first)
        }
    }

    private var labelColor: SwiftUI.Color {
        if activeState == .inactive {
            return SwiftUI.Color(nsColor: .tertiaryLabelColor)
        }
        let palette = themeModel.activeChrome
        if isActiveEditor { return palette?.text ?? .primary }
        return palette?.textSecondary ?? .secondary
    }

    private func select(_ item: JumpBarPathSegment.Item) {
        editorInstance.cursorPositions = [
            CursorPosition(line: item.line, column: item.column)
        ]
        model.cursorMoved(editorInstance.cursorPositions.first)
    }
}

/// One clickable path crumb. The menu lists siblings at the same level.
private struct JumpBarPathCrumb: View {
    let segment: JumpBarPathSegment
    let labelColor: SwiftUI.Color
    let select: (JumpBarPathSegment.Item) -> Void

    var body: some View {
        Menu {
            if segment.items.isEmpty {
                Button(segment.title) {}
                    .disabled(true)
            } else {
                ForEach(segment.items) { item in
                    Button {
                        select(item)
                    } label: {
                        Label(item.title, systemImage: item.systemImage)
                    }
                }
            }
        } label: {
            label
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(segment.items.isEmpty)
        .help(help)
    }

    private var label: some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.compact.right")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .scaleEffect(x: 1.30, y: 1.0, anchor: .center)
            Image(systemName: segment.systemImage)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(labelColor)
            Text(segment.title)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(labelColor)
                .lineLimit(1)
        }
        .frame(maxHeight: .infinity)
    }

    private var help: String {
        switch segment.role {
        case .function:
            return "Functions"
        case .variable:
            return "Variables"
        case .scope:
            return "Symbols"
        case .placeholder:
            return "No Selection"
        }
    }
}
