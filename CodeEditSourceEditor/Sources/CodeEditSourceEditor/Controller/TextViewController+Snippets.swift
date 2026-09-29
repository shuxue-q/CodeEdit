//
//  TextViewController+Snippets.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit Contributors on 9/29/26.
//

import AppKit
import CodeEditTextView

extension TextViewController {
    /// Inserts `snippet`, written in LSP snippet syntax, in place of `range`.
    ///
    /// When the snippet has numbered tab stops (`${1:placeholder}`, `$2`, …) the first one is selected
    /// and Tab / Shift-Tab move between them. The session ends at the final stop (`$0`, or the end of
    /// the snippet), when Escape is pressed, or when the selection leaves the snippet. Without tab
    /// stops the cursor is placed at `$0` or after the inserted text.
    public func insertSnippet(_ snippet: String, replacing range: NSRange) {
        endSnippetSession()
        let parsed = SnippetParser.parse(snippet)
        textView.replaceCharacters(in: range, with: parsed.text)

        // Edit filters can rewrite an insertion. Only track tab stops if the text went in unchanged.
        let insertedRange = NSRange(location: range.location, length: (parsed.text as NSString).length)
        let storage = textView.textStorage.string as NSString
        let insertedUnchanged = insertedRange.max <= storage.length
            && storage.substring(with: insertedRange) == parsed.text

        guard insertedUnchanged, let session = SnippetSession(snippet: parsed, location: range.location) else {
            if insertedUnchanged, let final = parsed.navigationGroups.last?.first {
                textView.selectionManager.setSelectedRange(
                    NSRange(location: range.location + final.location, length: 0)
                )
                textView.scrollSelectionToVisible()
            }
            return
        }
        snippetSession = session
        selectActiveSnippetTabStop()
        // The inserted lines are laid out on the next pass; outline the placeholders again after it.
        schedulePlaceholderLayerUpdate()
    }

    /// `true` while an inserted snippet's tab stops are being navigated.
    public var isSnippetSessionActive: Bool {
        snippetSession != nil
    }

    /// Moves to the next or previous tab stop of the active snippet.
    ///
    /// Moving forward from the last placeholder puts the cursor at the snippet's final stop and ends
    /// the session.
    /// - Returns: `false` when no snippet session is active.
    @discardableResult
    public func moveToSnippetTabStop(backwards: Bool = false) -> Bool {
        guard var session = snippetSession else { return false }
        if session.move(backwards: backwards) {
            snippetSession = session
        }
        selectActiveSnippetTabStop()
        return true
    }

    /// Ends the active snippet session, leaving the text and selection as they are.
    public func endSnippetSession() {
        guard snippetSession != nil else { return }
        snippetSession = nil
        removeSnippetPlaceholderLayers()
        for coordinator in textCoordinators.values() {
            coordinator.textViewDidChangeSnippetPlaceholder(controller: self, activeRanges: nil)
        }
    }

    // MARK: - Internal

    /// Selects the active tab stop's ranges. Reaching the final stop ends the session.
    private func selectActiveSnippetTabStop() {
        guard let session = snippetSession else { return }
        textView.selectionManager.setSelectedRanges(session.activeRanges)
        textView.scrollSelectionToVisible()
        guard !session.isAtFinalStop else {
            endSnippetSession()
            return
        }
        updateSnippetPlaceholderLayers()
        for coordinator in textCoordinators.values() {
            coordinator.textViewDidChangeSnippetPlaceholder(controller: self, activeRanges: session.activeRanges)
        }
    }

    /// Keeps the tab stops in place after `range` was replaced by `string`.
    func updateSnippetSession(afterReplacing range: NSRange, with string: String) {
        guard var session = snippetSession else { return }
        guard session.applyEdit(replacing: range, length: (string as NSString).length) else {
            endSnippetSession()
            return
        }
        snippetSession = session
        schedulePlaceholderLayerUpdate()
    }

    /// Redraws the placeholder outlines once the pending edit has been laid out.
    private func schedulePlaceholderLayerUpdate() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.snippetSession != nil else { return }
            self.textView.layoutSubtreeIfNeeded()
            self.updateSnippetPlaceholderLayers()
        }
    }

    /// Ends the session when a selection moves outside the snippet.
    func updateSnippetSessionForSelectionChange() {
        guard let session = snippetSession else { return }
        let selections = textView.selectionManager.textSelections.map(\.range)
        if !session.contains(selections: selections) {
            endSnippetSession()
        }
    }

    /// Redraws the placeholder outlines, for example after the text was laid out again.
    func updateSnippetPlaceholderLayers() {
        removeSnippetPlaceholderLayers()
        guard let session = snippetSession, let hostLayer = textView.layer else { return }
        textView.effectiveAppearance.performAsCurrentDrawingAppearance {
            let accent = NSColor.controlAccentColor
            for (range, isActive) in session.placeholderRanges where range.length > 0 {
                guard let path = textView.layoutManager.roundedPathForRange(range, cornerRadius: 3) else {
                    continue
                }
                let layer = CAShapeLayer()
                if #available(macOS 14.0, *) {
                    layer.path = path.cgPath
                } else {
                    layer.path = path.cgPathFallback
                }
                layer.fillColor = accent.withAlphaComponent(isActive ? 0.2 : 0.1).cgColor
                layer.strokeColor = accent.withAlphaComponent(isActive ? 0.7 : 0.35).cgColor
                layer.lineWidth = 1
                // Below the line fragment views, so the text draws on top.
                hostLayer.insertSublayer(layer, at: 0)
                snippetPlaceholderLayers.append(layer)
            }
        }
    }

    private func removeSnippetPlaceholderLayers() {
        snippetPlaceholderLayers.forEach { $0.removeFromSuperlayer() }
        snippetPlaceholderLayers.removeAll()
    }
}
