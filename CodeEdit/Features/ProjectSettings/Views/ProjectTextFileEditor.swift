//
//  ProjectTextFileEditor.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/30/26.
//

import SwiftUI

/// Edits a ``ProjectTextFile``, with a notice when the file changed on disk while it had unsaved
/// edits. Save and Revert sit above the text so they stay visible in a scrolled form.
struct ProjectTextFileEditor: View {
    @Bindable var file: ProjectTextFile
    /// Opens the file in an editor tab; hidden when `nil`.
    var openInTab: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if file.changedOnDisk {
                HStack {
                    Label("\(file.displayPath) changed on disk.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Reload") { file.revert() }
                }
                .font(.callout)
            }

            HStack(spacing: 8) {
                if let error = file.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                } else if !file.exists {
                    Text("\(file.displayPath) does not exist. Saving creates it.")
                        .foregroundStyle(.secondary)
                } else if file.hasUnsavedChanges {
                    Text("Edited")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let openInTab, file.exists {
                    Button("Open in Tab", action: openInTab)
                }
                Button("Revert") { file.revert() }
                    .disabled(!file.hasUnsavedChanges && !file.changedOnDisk)
                Button(file.exists ? "Save" : "Create") { file.save() }
                    .disabled(file.exists && !file.hasUnsavedChanges && !file.changedOnDisk)
                    .accessibilityIdentifier("ProjectTextFileSave")
            }
            .font(.callout)

            PlainTextEditor(text: $file.text)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(nsColor: .separatorColor)))
                .accessibilityIdentifier("ProjectTextFileEditor")
        }
    }
}

/// A monospaced plain-text view with smart quotes, dashes, and autocorrection turned off, for
/// configuration files where those substitutions would corrupt the contents.
private struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
