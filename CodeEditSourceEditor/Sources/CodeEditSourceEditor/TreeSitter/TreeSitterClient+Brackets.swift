//
//  TreeSitterClient+Brackets.swift
//  CodeEditSourceEditor
//
//  Created by Claude on 9/29/26.
//

import Foundation
import SwiftTreeSitter

extension TreeSitterClient {
    /// Whether a UTF-16 code unit is one of the bracket characters used for rainbow coloring.
    static func isBracketCharacter(_ unit: unichar) -> Bool {
        switch unit {
        case 0x28, 0x29, 0x5B, 0x5D, 0x7B, 0x7D: // ( ) [ ] { }
            return true
        default:
            return false
        }
    }

    /// Returns `+1` for an opening bracket node type, `-1` for a closing one, and `0` otherwise.
    private static func bracketDirection(of type: String?) -> Int {
        switch type {
        case "(", "[", "{": return 1
        case ")", "]", "}": return -1
        default: return 0
        }
    }

    /// Finds every `()`, `[]` and `{}` token in `range` and assigns it a rainbow level from its nesting depth.
    ///
    /// Brackets are recognised as single-character *anonymous leaf nodes* of the syntax tree, so brackets inside
    /// strings, comments and regex literals are never counted. Depth counts every enclosing bracket of any kind, and
    /// an opening bracket shares its level with the matching closing one.
    ///
    /// The cost is proportional to the tree depth plus the number of tokens in `range`, not the document size: the
    /// starting depth is found by walking down the ancestors of `range.location` and only inspecting the siblings
    /// before it, then the tokens inside the range are visited once in document order.
    ///
    /// - Parameters:
    ///   - layer: The (primary) language layer whose tree is walked.
    ///   - range: The range to produce bracket highlights for.
    /// - Returns: One single-character ``HighlightRange`` per bracket, ordered by location.
    func bracketHighlights(layer: LanguageLayer, range: NSRange) -> [HighlightRange] {
        guard range.length > 0, let root = layer.tree?.rootNode else { return [] }
        // Tree-sitter offsets are UTF-16 code units * 2 (bytes).
        let startByte = UInt32(range.location * 2)
        let endByte = UInt32(range.upperBound * 2)
        let depth = Self.bracketDepth(at: startByte, in: root)
        return Self.bracketTokens(from: startByte, to: endByte, startingDepth: depth, in: root)
    }

    /// The bracket nesting depth at `startByte`: descends towards it, counting brackets among the earlier siblings at
    /// each level.
    private static func bracketDepth(at startByte: UInt32, in root: Node) -> Int {
        let cursor = root.treeCursor
        var depth = 0
        descend: while cursor.goToFirstChild() {
            while let child = cursor.currentNode {
                let bytes = child.byteRange
                if bytes.upperBound <= startByte {
                    if bytes.upperBound - bytes.lowerBound == 2, child.childCount == 0 {
                        depth += bracketDirection(of: child.nodeType)
                    }
                    if !cursor.gotoNextSibling() { break descend }
                } else if bytes.lowerBound < startByte {
                    continue descend // Contains the start position, so its own children are ancestors.
                } else {
                    break descend // Starts at or after the range.
                }
            }
        }
        return max(depth, 0)
    }

    /// Walks the leaf tokens in `startByte..<endByte` in document order, emitting a level for each bracket.
    private static func bracketTokens(
        from startByte: UInt32,
        to endByte: UInt32,
        startingDepth: Int,
        in root: Node
    ) -> [HighlightRange] {
        var depth = startingDepth
        let walker = root.treeCursor
        while walker.goToFirstChild(for: startByte) { }
        var highlights: [HighlightRange] = []
        while let node = walker.currentNode {
            let bytes = node.byteRange
            if bytes.lowerBound >= endByte { break }
            if bytes.lowerBound >= startByte, bytes.upperBound - bytes.lowerBound == 2, node.childCount == 0 {
                let direction = bracketDirection(of: node.nodeType)
                if direction < 0 { depth = max(depth - 1, 0) }
                if direction != 0 {
                    highlights.append(HighlightRange(
                        range: NSRange(location: Int(bytes.lowerBound / 2), length: 1),
                        capture: .bracketLevel(depth)
                    ))
                }
                if direction > 0 { depth += 1 }
            }
            // Advance to the next leaf in document order.
            while !walker.gotoNextSibling() {
                if !walker.gotoParent() { return highlights }
            }
            while walker.goToFirstChild() { }
        }
        return highlights
    }

    /// Overlays `brackets` on `highlights`, so a bracket token always takes the rainbow color even when a grammar
    /// query also captured it (or a larger range containing it).
    /// - Parameters:
    ///   - brackets: Single-character bracket highlights, ordered by location.
    ///   - highlights: Grammar highlights, ordered by location. May overlap.
    /// - Returns: The merged highlights, ordered by location.
    static func overlay(brackets: [HighlightRange], on highlights: [HighlightRange]) -> [HighlightRange] {
        guard !brackets.isEmpty else { return highlights }
        guard !highlights.isEmpty else { return brackets }

        var result: [HighlightRange] = []
        result.reserveCapacity(highlights.count + brackets.count)
        var nextBracket = 0

        for highlight in highlights {
            var start = highlight.range.location
            let end = highlight.range.upperBound
            // Emit brackets that come before the end of this highlight, splitting the highlight around them.
            while nextBracket < brackets.count, brackets[nextBracket].range.location < end {
                let bracket = brackets[nextBracket]
                nextBracket += 1
                if bracket.range.location >= start {
                    if bracket.range.location > start {
                        let head = NSRange(location: start, length: bracket.range.location - start)
                        result.append(highlight.trimmed(to: head))
                    }
                    start = bracket.range.upperBound
                }
                // Otherwise the bracket sits in a gap before this highlight, and is emitted unsplit.
                result.append(bracket)
            }
            if start < end {
                result.append(highlight.trimmed(to: NSRange(location: start, length: end - start)))
            }
        }
        result.append(contentsOf: brackets[nextBracket...])
        return result
    }
}

private extension HighlightRange {
    func trimmed(to range: NSRange) -> HighlightRange {
        HighlightRange(range: range, capture: capture, modifiers: modifiers)
    }
}
