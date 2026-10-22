//
//  CreateCodeSnippetView.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit on 2024.
//

import SwiftUI

/// A SwiftUI view for creating and saving code snippets.
public struct CreateCodeSnippetView: View {
    @State private var title: String
    @State private var summary: String
    @State private var shortcut: String
    @State private var code: String
    private let onSave: (CodeSnippet) -> Void
    private let onCancel: () -> Void

    public init(
        initialCode: String = "",
        initialTitle: String? = nil,
        onSave: @escaping (CodeSnippet) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._title = State(initialValue: initialTitle ?? String(localized: "My Snippet", bundle: .module))
        self._summary = State(initialValue: "")
        self._shortcut = State(initialValue: "")
        self._code = State(initialValue: initialCode)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Code Snippet", bundle: .module)
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Title:", bundle: .module)
                        .frame(width: 120, alignment: .trailing)
                    TextField(String(localized: "Title", bundle: .module), text: $title)
                }

                HStack {
                    Text("Completion Shortcut:", bundle: .module)
                        .frame(width: 120, alignment: .trailing)
                    TextField(String(localized: "Shortcut", bundle: .module), text: $shortcut)
                }

                HStack {
                    Text("Summary:", bundle: .module)
                        .frame(width: 120, alignment: .trailing)
                    TextField(String(localized: "Description", bundle: .module), text: $summary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Snippet Code:", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextEditor(text: $code)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120, maxHeight: 220)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }

            HStack {
                Spacer()
                Button(role: .cancel) {
                    onCancel()
                } label: {
                    Text("Cancel", bundle: .module)
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    let snippet = CodeSnippet(
                        title: title.isEmpty ? String(localized: "Snippet", bundle: .module) : title,
                        summary: summary,
                        shortcut: shortcut,
                        code: code
                    )
                    onSave(snippet)
                } label: {
                    Text("Save", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 440)
    }
}
