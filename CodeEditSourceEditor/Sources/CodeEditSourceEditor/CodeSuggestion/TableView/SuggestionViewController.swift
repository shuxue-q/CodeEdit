//
//  SuggestionViewController.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 7/22/25.
//

import AppKit
import SwiftUI
import Combine

class SuggestionViewController: NSViewController {
    var tintView: NSView = NSView()
    var tableView: NSTableView = NSTableView()
    var scrollView: NSScrollView = NSScrollView()
    var noItemsLabel: NSTextField = NSTextField(labelWithString: "No Completions")
    var previewView: CodeSuggestionPreviewView = CodeSuggestionPreviewView()

    var viewHeightConstraint: NSLayoutConstraint?
    var viewWidthConstraint: NSLayoutConstraint?
    var previewWidthConstraint: NSLayoutConstraint?
    var footerView = NSView()
    var footerSeparator = NSView()
    var originLabel = NSTextField(labelWithString: "")
    var footerHeightConstraint: NSLayoutConstraint?

    /// Labels currently shown. A resolve replaces one item without changing these.
    var displayedLabels: [String] = []
    var isResettingItems = false
    var resolveTask: Task<Void, Never>?
    var resolveGeneration = 0

    var itemObserver: AnyCancellable?
    var cachedFont: NSFont?

    weak var model: SuggestionViewModel? {
        didSet {
            itemObserver?.cancel()
            itemObserver = model?.$items.receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.onItemsUpdated()
            }
        }
    }

    /// An event monitor for keyboard events
    private var localEventMonitor: Any?

    weak var windowController: SuggestionController?

    override func loadView() {
        super.loadView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8.5
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.wantsLayer = true
        tintView.layer?.cornerRadius = 8.5
        tintView.layer?.backgroundColor = .clear
        view.addSubview(tintView)

        configureTableView()
        configureScrollView()

        noItemsLabel.textColor = .secondaryLabelColor
        noItemsLabel.alignment = .center
        noItemsLabel.translatesAutoresizingMaskIntoConstraints = false
        noItemsLabel.isHidden = false

        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.isHidden = true
        previewWidthConstraint = previewView.widthAnchor.constraint(equalToConstant: 0)
        configureFooter()

        view.addSubview(noItemsLabel)
        view.addSubview(scrollView)
        view.addSubview(footerView)
        view.addSubview(previewView)

        NSLayoutConstraint.activate([
            tintView.topAnchor.constraint(equalTo: view.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tintView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // Centered, not pinned to the top and bottom. A hidden label pinned to both
            // edges still reports its line height, and the next layout pass (arrowing
            // through suggestions) collapses the window to that single line.
            noItemsLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            noItemsLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: previewView.leadingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerView.topAnchor),

            footerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: previewView.leadingAnchor),
            footerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footerHeightConstraint!,

            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            previewWidthConstraint!
        ])
    }

    private func configureFooter() {
        footerView.translatesAutoresizingMaskIntoConstraints = false
        footerView.clipsToBounds = true
        footerView.isHidden = true
        footerHeightConstraint = footerView.heightAnchor.constraint(equalToConstant: 0)

        footerSeparator.translatesAutoresizingMaskIntoConstraints = false
        footerSeparator.wantsLayer = true
        footerSeparator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        footerView.addSubview(footerSeparator)

        originLabel.translatesAutoresizingMaskIntoConstraints = false
        originLabel.font = .systemFont(ofSize: 12)
        originLabel.lineBreakMode = .byTruncatingMiddle
        originLabel.maximumNumberOfLines = 1
        originLabel.isEditable = false
        originLabel.isSelectable = false
        originLabel.isBezeled = false
        originLabel.drawsBackground = false
        originLabel.backgroundColor = .clear
        originLabel.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        footerView.addSubview(originLabel)

        NSLayoutConstraint.activate([
            footerSeparator.topAnchor.constraint(equalTo: footerView.topAnchor),
            footerSeparator.leadingAnchor.constraint(equalTo: footerView.leadingAnchor),
            footerSeparator.trailingAnchor.constraint(equalTo: footerView.trailingAnchor),
            footerSeparator.heightAnchor.constraint(equalToConstant: 1),

            originLabel.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: 13),
            originLabel.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -13),
            originLabel.centerYAnchor.constraint(equalTo: footerView.centerYAnchor, constant: 0.5)
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        resetScrollPosition()
        tableView.reloadData()
        if let controller = model?.activeTextView {
            styleView(using: controller)
        }
        setupEventMonitors()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        resolveTask?.cancel()
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }

    private func setupEventMonitors() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown]
        ) { [weak self] event in
            guard let self = self else { return event }

            switch event.type {
            case .keyDown:
                return checkKeyDownEvents(event)
            default:
                return event
            }
        }
    }

    private func checkKeyDownEvents(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 53: // Escape
            windowController?.close()
            return nil

        case 125: // Down Arrow
            moveSelection(by: 1)
            return nil

        case 126: // Up Arrow
            moveSelection(by: -1)
            return nil

        case 36, 48:  // Return/Tab
            self.applySelectedItem()
            return nil

        default:
            return event
        }
    }

    /// Moves the highlighted row and refreshes its documentation.
    ///
    /// Arrow keys are delivered through a local monitor because this panel cannot become key.
    /// `NSTableView.keyDown` does not reliably change the selection in that case, so the preview
    /// stayed on whatever item was drawn first.
    func moveSelection(by delta: Int) {
        let count = model?.items.count ?? 0
        guard count > 0, delta != 0 else { return }
        let current = tableView.selectedRow
        let next: Int
        if current < 0 {
            next = delta > 0 ? 0 : count - 1
        } else {
            next = min(max(current + delta, 0), count - 1)
        }
        guard next != current else { return }
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }
}
