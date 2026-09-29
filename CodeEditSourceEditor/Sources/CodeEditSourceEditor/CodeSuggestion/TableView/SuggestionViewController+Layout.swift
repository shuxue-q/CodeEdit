//
//  SuggestionViewController+Layout.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit Contributors on 9/27/26.
//

import AppKit
import SwiftUI

extension SuggestionViewController {
    func styleView(using controller: TextViewController) {
        noItemsLabel.font = controller.font
        previewView.font = controller.font
        previewView.documentationFont = controller.font
        previewView.theme = controller.theme
        switch controller.systemAppearance {
        case .aqua:
            let color = controller.theme.background
            if color != .clear {
                let newColor = NSColor(
                    red: color.redComponent * 0.95,
                    green: color.greenComponent * 0.95,
                    blue: color.blueComponent * 0.95,
                    alpha: 1.0
                )
                tintView.layer?.backgroundColor = newColor.cgColor
            } else {
                tintView.layer?.backgroundColor = .clear
            }
        case .darkAqua:
            tintView.layer?.backgroundColor = controller.theme.background.cgColor
        default:
            return
        }
        updateSize(using: controller)
    }

    func updateSize(using controller: TextViewController?) {
        guard let items = model?.items, !items.isEmpty else {
            previewWidthConstraint?.constant = 0
            footerHeightConstraint?.constant = 0
            footerView.isHidden = true
            let size = NSSize(width: 256, height: noItemsLabel.fittingSize.height + 20)
            preferredContentSize = size
            windowController?.updateWindowSize(newSize: size)
            return
        }

        if let controller {
            cachedFont = controller.font
        }
        let font = controller?.font ?? cachedFont ?? NSFont.systemFont(ofSize: 12)

        let listWidth = SuggestionListLayout.listWidth(items: items, font: font)
        if let column = tableView.tableColumns.first {
            column.width = listWidth
        }

        let rowHeight = SuggestionListLayout.rowHeight(font: font, sample: items.first)
        SuggestionListLayout.apply(rowHeight: rowHeight, to: tableView)
        let previewVisible = !previewView.isHidden
        previewWidthConstraint?.constant = previewVisible ? SuggestionController.PREVIEW_WIDTH : 0
        let previewHeight = previewVisible
            ? previewView.contentHeight(forWidth: SuggestionController.PREVIEW_WIDTH)
            : 0
        let screenHeight = view.window?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height
        let listHeight = SuggestionWindowMeasurement(
            rowHeight: rowHeight,
            itemCount: items.count,
            maxVisibleRows: visibleRowLimit,
            verticalPadding: SuggestionController.WINDOW_PADDING,
            previewHeight: previewHeight,
            screenLimit: SuggestionListLayout.screenLimit(height: screenHeight)
        ).contentHeight
        let height = listHeight + (footerHeightConstraint?.constant ?? 0)

        viewHeightConstraint?.isActive = false
        viewWidthConstraint?.isActive = false

        let newWidth = listWidth + (previewVisible ? SuggestionController.PREVIEW_WIDTH : 0)
        viewHeightConstraint = view.heightAnchor.constraint(equalToConstant: height)
        viewWidthConstraint = view.widthAnchor.constraint(equalToConstant: newWidth)

        viewHeightConstraint?.isActive = true
        viewWidthConstraint?.isActive = true

        view.updateConstraintsForSubtreeIfNeeded()
        view.layoutSubtreeIfNeeded()

        let newSize = NSSize(width: newWidth, height: height)
        preferredContentSize = newSize
        windowController?.updateWindowSize(newSize: newSize)
        refreshRows()
    }

    func configureTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = .zero
        tableView.allowsEmptySelection = false
        tableView.selectionHighlightStyle = .regular
        tableView.style = .plain
        tableView.usesAutomaticRowHeights = false
        tableView.rowSizeStyle = .custom
        tableView.gridStyleMask = []
        tableView.target = self
        tableView.action = #selector(tableViewClicked(_:))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ItemsCell"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    }

    func configureScrollView() {
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.verticalScroller = NoSlotScroller()
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.verticalScrollElasticity = .allowed
        scrollView.contentInsets = NSEdgeInsets(
            top: SuggestionController.WINDOW_PADDING,
            left: 0,
            bottom: SuggestionController.WINDOW_PADDING,
            right: 0
        )
    }

    func onItemsUpdated() {
        let labels = model?.items.map(\.label) ?? []
        // Resolve writes one item back. Keep the highlight instead of jumping to the first row.
        if !labels.isEmpty, labels == displayedLabels {
            applyPreview(resolving: false)
            updateSize(using: model?.activeTextView)
            return
        }

        displayedLabels = labels
        resolveTask?.cancel()
        resetScrollPosition()
        if let model {
            noItemsLabel.isHidden = !model.items.isEmpty
            scrollView.isHidden = model.items.isEmpty
        }
        isResettingItems = true
        tableView.reloadData()
        if model?.items.isEmpty == false, tableView.selectedRow != 0 {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        isResettingItems = false
        // Selecting row 0 before the table has rows never posts selectionDidChange, so the
        // first item's documentation was never applied.
        applyPreview(resolving: true)
        if let activeTextView = model?.activeTextView {
            updateSize(using: activeTextView)
        }
    }

    @objc
    private func tableViewClicked(_ sender: Any?) {
        if NSApp.currentEvent?.clickCount == 2 {
            applySelectedItem()
        }
    }

    func resetScrollPosition() {
        let clipView = scrollView.contentView

        // Scroll to the top of the content. The row selection happens after reloadData.
        clipView.scroll(to: NSPoint(x: 0, y: -SuggestionController.WINDOW_PADDING))
    }

    func applySelectedItem() {
        let row = tableView.selectedRow
        guard row >= 0, row < model?.items.count ?? 0 else {
            return
        }
        if let model {
            model.applySelectedItem(item: model.items[tableView.selectedRow], window: view.window)
        }
    }

    private var visibleRowLimit: CGFloat {
        let count = model?.activeTextView?.configuration.peripherals.visibleCompletionCount
            ?? SuggestionController.defaultVisibleRows
        return CGFloat(min(20, max(1, count)))
    }
}
