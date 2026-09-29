//
//  LineFoldStorage.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 5/7/25.
//
import _RopeModule
import Foundation

/// Sendable data model for code folding using RangeStore
struct LineFoldStorage: Sendable {
    /// A temporary fold representation without stable ID
    struct RawFold: Sendable {
        let depth: Int
        let range: Range<Int>
    }

    struct DepthStartPair: Hashable {
        let depth: Int
        let start: Int
    }

    /// Element stored in RangeStore: holds reference to a fold region
    struct FoldStoreElement: RangeStoreElement, Sendable {
        let id: FoldRange.FoldIdentifier
        let depth: Int

        var isEmpty: Bool { false }
    }

    private var idCounter = FoldRange.FoldIdentifier.zero
    private var store: RangeStore<FoldStoreElement>
    private var foldRanges: [FoldRange.FoldIdentifier: FoldRange] = [:]
    /// The fold that directly encloses each nested fold, keyed by the nested fold's id.
    private var parentIDs: [FoldRange.FoldIdentifier: FoldRange.FoldIdentifier] = [:]

    /// Initialize with the full document length
    init(documentLength: Int, folds: [RawFold] = [], collapsedRanges: Set<DepthStartPair> = []) {
        self.store = RangeStore<FoldStoreElement>(documentLength: documentLength)
        self.updateFolds(from: folds, collapsedRanges: collapsedRanges)
    }

    private mutating func nextFoldId() -> FoldRange.FoldIdentifier {
        idCounter += 1
        return idCounter
    }

    /// Replace all fold data from raw folds, preserving collapse state via callback
    /// - Parameter rawFolds: newly computed folds (depth + range)
    /// - Parameter collapsedRanges: Current collapsed ranges/depths
    mutating func updateFolds(from rawFolds: [RawFold], collapsedRanges: Set<DepthStartPair>) {
        // Build reuse map by start+depth, carry over collapse state
        var reuseMap: [DepthStartPair: FoldRange] = [:]
        for region in foldRanges.values {
            reuseMap[DepthStartPair(depth: region.depth, start: region.range.lowerBound)] = region
        }

        // Build new regions
        foldRanges.removeAll(keepingCapacity: true)
        parentIDs.removeAll(keepingCapacity: true)
        store = RangeStore<FoldStoreElement>(documentLength: store.length)

        // Folds nest and arrive sorted by start, so the folds on this stack that haven't ended enclose the next one.
        var enclosingFolds: [FoldRange] = []

        for raw in rawFolds {
            let key = DepthStartPair(depth: raw.depth, start: raw.range.lowerBound)
            // reuse id and collapse state if available
            let prior = reuseMap[key]
            let id = prior?.id ?? nextFoldId()
            let wasCollapsed = prior?.isCollapsed ?? false
            // override collapse if provider says so
            let isCollapsed = collapsedRanges.contains(key) || wasCollapsed
            let fold = FoldRange(id: id, depth: raw.depth, range: raw.range, isCollapsed: isCollapsed)

            while let last = enclosingFolds.last, last.range.upperBound <= raw.range.lowerBound {
                enclosingFolds.removeLast()
            }
            parentIDs[id] = enclosingFolds.last?.id
            enclosingFolds.append(fold)

            foldRanges[id] = fold
            let elem = FoldStoreElement(id: id, depth: raw.depth)
            store.set(value: elem, for: raw.range)
        }
    }

    /// Keep folding offsets in sync after text edits
    mutating func storageUpdated(editedRange: NSRange, changeInLength delta: Int) {
        store.storageUpdated(editedRange: editedRange, changeInLength: delta)
    }

    mutating func toggleCollapse(forFold fold: FoldRange) {
        guard var existingRange = foldRanges[fold.id] else { return }
        existingRange.isCollapsed.toggle()
        foldRanges[fold.id] = existingRange
    }

    /// Query a document subrange and return all folds as an ordered list by start position
    func folds(in queryRange: Range<Int>) -> [FoldRange] {
        let runs = store.runs(in: queryRange.clamped(to: 0..<store.length))
        var alreadyReturnedIDs: Set<FoldRange.FoldIdentifier> = []
        var result: [FoldRange] = []

        for run in runs {
            if let elem = run.value, !alreadyReturnedIDs.contains(elem.id), let range = foldRanges[elem.id] {
                result.append(
                    FoldRange(
                        id: elem.id,
                        depth: elem.depth,
                        range: range.range,
                        isCollapsed: range.isCollapsed
                    )
                )
                alreadyReturnedIDs.insert(elem.id)
            }
        }

        return result.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// Query a document subrange and return every fold that overlaps it, ordered by start position.
    ///
    /// The store only keeps the innermost fold at each offset, so ``folds(in:)`` misses an enclosing fold when nested
    /// folds cover all of its text in the range. This walks up from each of those folds to add its ancestors.
    func folds(overlapping queryRange: Range<Int>) -> [FoldRange] {
        let innermost = folds(in: queryRange)
        var seenIDs = Set(innermost.map(\.id))
        var result = innermost

        for fold in innermost {
            var parentID = parentIDs[fold.id]
            // Stop at a fold already listed: its ancestors are added from wherever it was listed.
            while let id = parentID, seenIDs.insert(id).inserted, let parent = foldRanges[id] {
                result.append(parent)
                parentID = parentIDs[id]
            }
        }

        return result.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
}
