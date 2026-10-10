//
//  TreeSitterClient+Highlight.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 3/10/23.
//

import Foundation
import SwiftTreeSitter
import CodeEditLanguages

extension TreeSitterClient {
    func queryHighlightsForRange(range: NSRange) -> [HighlightRange] {
        guard let state = self.state else { return [] }

        var highlights: [HighlightRange] = []
        var injectedSet = IndexSet(integersIn: range)

        for layer in state.layers where layer.id != state.primaryLayer.id {
            // Query injected only if a layer's ranges intersects with `range`
            for layerRange in layer.ranges {
                if let rangeIntersection = range.intersection(layerRange) {
                    let queryResult = queryLayerHighlights(
                        layer: layer,
                        range: rangeIntersection
                    )

                    highlights.append(contentsOf: queryResult)
                    injectedSet.remove(integersIn: rangeIntersection)
                }
            }
        }

        // Query primary for any ranges that weren't used in the injected layers.
        for range in injectedSet.rangeView {
            let queryResult = queryLayerHighlights(
                layer: state.layers[0],
                range: NSRange(range)
            )
            highlights.append(contentsOf: queryResult)
        }

        // Rainbow brackets: layered over grammar captures so bracket tokens always take their depth color.
        if let primary = state.layers.first {
            let brackets = bracketHighlights(layer: primary, range: range)
            if !brackets.isEmpty {
                let sorted = highlights.sorted { $0.range.location < $1.range.location }
                highlights = Self.overlay(brackets: brackets, on: sorted)
            }
        }

        return highlights
    }

    /// Queries the given language layer for any highlights.
    /// - Parameters:
    ///   - layer: The layer to query.
    ///   - range: The range to query for.
    /// - Returns: Any ranges to highlight.
    internal func queryLayerHighlights(
        layer: LanguageLayer,
        range: NSRange
    ) -> [HighlightRange] {
        guard let tree = layer.tree,
              let rootNode = tree.rootNode else {
            return []
        }

        // This needs to be on the main thread since we're going to use the `textProvider` in
        // the `highlightsFromCursor` method, which uses the textView's text storage.
        guard let queryCursor = layer.languageQuery?.execute(node: rootNode, in: tree) else {
            return []
        }
        queryCursor.setRange(range)
        queryCursor.matchLimit =  Constants.matchLimit

        var highlights: [HighlightRange] = []

        // See https://github.com/CodeEditApp/CodeEditSourceEditor/pull/228
        if layer.id == .jsdoc {
            highlights.append(HighlightRange(range: range, capture: .comment))
        }

        highlights += highlightsFromCursor(cursor: queryCursor, includedRange: range)

        return highlights
    }

    /// Resolves a query cursor to the highlight ranges it contains.
    /// **Must be called on the main thread**
    /// - Parameters:
    ///     - cursor: The cursor to resolve.
    ///     - includedRange: The range to include highlights from.
    /// - Returns: Any highlight ranges contained in the cursor.
    internal func highlightsFromCursor(
        cursor: QueryCursor,
        includedRange: NSRange
    ) -> [HighlightRange] {
        guard let readCallback else { return [] }
        // Several patterns can capture the same range (`(identifier) @variable` and a more specific pattern for the
        // same identifier). Providers apply the first highlight they see for a range and skip later overlapping
        // ones, so exactly one highlight per range is emitted: the capture with the lowest index, which is the one
        // named first in the query. It keeps the position of the first capture seen for that range.
        var levels: [NSRange: Int] = [:]
        var slots: [NSRange: Int] = [:]
        var highlights: [HighlightRange?] = []
        let captures = cursor
            .resolve(with: .init(textProvider: readCallback)) // Resolve our cursor against the query
            .flatMap { $0.captures }
            .reversed() // SwiftTreeSitter returns captures in the reverse order of what we need to filter with.

        for capture in captures {
            let range = capture.range
            let index = capture.index

            // Lower indexed captures are favored over higher, this is why we reverse it above
            if let existingLevel = levels[range], existingLevel <= index {
                continue
            }

            guard let captureName = CaptureName.fromString(capture.name) else {
                continue
            }

            // Update the filter level to the current index since it's lower and a 'valid' capture
            levels[range] = index

            // Validate range and capture name
            let intersectionRange = range.intersection(includedRange) ?? .zero
            let highlight = intersectionRange.length > 0
                ? HighlightRange(range: intersectionRange, capture: captureName)
                : nil

            if let slot = slots[range] {
                highlights[slot] = highlight
            } else {
                slots[range] = highlights.count
                highlights.append(highlight)
            }
        }
        return highlights.compactMap { $0 }
    }
}
