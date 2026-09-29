//
//  SuggestionViewController+Rows.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit Contributors on 9/27/26.
//

import AppKit
import SwiftUI

extension SuggestionViewController: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int {
        model?.items.count ?? 0
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let model = model,
              row >= 0, row < model.items.count,
              model.activeTextView != nil else {
            return nil
        }
        let hostingView = NSHostingView(rootView: labelView(for: model.items[row], row: row))
        // Keep the row at its text height. Without this the hosting view adopts the table's
        // offered height and a single selected row fills the window.
        hostingView.sizingOptions = .intrinsicContentSize
        return hostingView
    }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = CodeSuggestionRowView { [weak self] in
            self?.model?.activeTextView?.theme.background ?? NSColor.controlBackgroundColor
        }
        rowView.usesAccentSelection = showsInlineCompletionInfo
        return rowView
    }

    public func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        // Only allow selection through keyboard navigation or single clicks
        NSApp.currentEvent?.type != .leftMouseDragged
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isResettingItems else { return }
        guard let model,
              tableView.selectedRow >= 0,
              tableView.selectedRow < model.items.count else {
            return
        }
        let selectedItem = model.items[tableView.selectedRow]
        applyPreview(resolving: true)
        updateSize(using: nil)
        model.didSelect(item: selectedItem)
    }
}

extension SuggestionViewController {
    /// Reloads the inline layout after a settings change.
    func configurationChanged() {
        refreshRows()
        applyPreview(resolving: false)
        updateSize(using: model?.activeTextView)
    }

    func applyPreview(resolving: Bool) {
        guard let model,
              tableView.selectedRow >= 0,
              model.items.indices.contains(tableView.selectedRow) else {
            previewView.documentation = nil
            previewView.sourcePreview = nil
            previewView.pathComponents = []
            previewView.isHidden = true
            updateOriginFooter(for: nil)
            if resolving {
                resolveTask?.cancel()
            }
            return
        }

        let row = tableView.selectedRow
        let item = model.items[row]
        previewView.sourcePreview = model.syntaxHighlights(forIndex: row)
        previewView.documentation = SuggestionPreviewContent.text(for: item)
        previewView.pathComponents = item.pathComponents ?? []
        previewView.targetRange = item.targetPosition
        previewView.isHidden = showsInlineCompletionInfo || model.items.isEmpty
        updateOriginFooter(for: item)
        if resolving {
            scheduleResolve(for: item, row: row)
        }
    }

    func refreshRows() {
        let inline = showsInlineCompletionInfo
        guard let model else { return }
        for row in 0..<tableView.numberOfRows {
            guard model.items.indices.contains(row) else { continue }
            if let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) as? CodeSuggestionRowView {
                rowView.usesAccentSelection = inline
                rowView.needsDisplay = true
            }
            guard let host = tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
                    as? NSHostingView<CodeSuggestionLabelView> else {
                continue
            }
            host.sizingOptions = .intrinsicContentSize
            host.rootView = labelView(for: model.items[row], row: row)
        }
    }

    private var showsInlineCompletionInfo: Bool {
        model?.activeTextView?.configuration.peripherals.showInlineCompletionInfo ?? false
    }

    private func scheduleResolve(for item: CodeSuggestionEntry, row: Int) {
        resolveTask?.cancel()
        resolveGeneration += 1
        let generation = resolveGeneration
        resolveTask = Task { @MainActor in
            let resolved = await self.model?.resolve(item: item)
            guard !Task.isCancelled, generation == self.resolveGeneration else { return }
            guard self.tableView.selectedRow == row, let resolved else { return }
            self.model?.replaceItem(at: row, with: resolved)
        }
    }

    private func updateOriginFooter(for item: CodeSuggestionEntry?) {
        let header = showsInlineCompletionInfo
            ? SuggestionOrigin.header(in: item?.documentation) ?? SuggestionOrigin.header(in: item?.detail)
            : nil
        let showsFooter = header != nil
        footerView.isHidden = !showsFooter
        let font = model?.activeTextView?.font ?? originLabel.font ?? .systemFont(ofSize: 12)
        if let header {
            originLabel.attributedStringValue = originText(header: header, font: font)
            footerHeightConstraint?.constant = max(CGFloat(28), CGFloat(ceil(font.lineHeight)) + 14)
        } else {
            originLabel.stringValue = ""
            footerHeightConstraint?.constant = 0
        }
    }

    private func originText(header: String, font: NSFont) -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: "From ",
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor
            ]
        )
        let chipFont = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
        text.append(NSAttributedString(
            string: header,
            attributes: [
                .font: chipFont,
                .foregroundColor: NSColor.controlAccentColor,
                .backgroundColor: NSColor.quaternaryLabelColor
            ]
        ))
        return text
    }

    private func labelView(for suggestion: CodeSuggestionEntry, row: Int) -> CodeSuggestionLabelView {
        let textView = model?.activeTextView
        let font = textView?.font ?? cachedFont ?? .systemFont(ofSize: 12)
        let labelColor = textView?.theme.text.color ?? .labelColor
        return CodeSuggestionLabelView(
            suggestion: suggestion,
            labelColor: labelColor,
            secondaryLabelColor: labelColor.withAlphaComponent(0.5),
            font: font,
            showsTrailingDetail: showsInlineCompletionInfo,
            isSelected: showsInlineCompletionInfo && tableView.selectedRow == row
        )
    }
}
