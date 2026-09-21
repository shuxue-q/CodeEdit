//
//  LSPHoverView+Discussion.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/17/26.
//

import AppKit
import SwiftUI

// MARK: - Discussion Section Extension

extension LSPHoverView {
    func discussionSection(_ discussion: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let blocks = Self.parseDiscussionBlocks(discussion)
            ForEach(blocks) { block in
                if block.isCode {
                    Text(LSPCodeHighlighter.highlight(
                        code: block.text,
                        symbolName: LSPHoverSectionExtractor.extractSymbolName(from: block.text),
                        theme: themeModel.selectedTheme?.editor
                    ))
                    .textSelection(.enabled)
                    .font(.system(size: 11.5, design: .monospaced))
                    .padding(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
                } else {
                    Text(LSPCodeHighlighter.highlightInlineMarkdown(
                        text: block.text,
                        theme: themeModel.selectedTheme?.editor
                    ))
                    .textSelection(.enabled)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    struct DiscussionBlock: Identifiable, Equatable {
        let id: UUID
        var isCode: Bool
        var text: String

        init(isCode: Bool, text: String) {
            self.id = UUID()
            self.isCode = isCode
            self.text = text
        }
    }

    static func parseDiscussionBlocks(_ text: String) -> [DiscussionBlock] {
        var blocks: [DiscussionBlock] = []
        let lines = text.components(separatedBy: "\n")
        var currentLines: [String] = []
        var inFenced = false
        var inDef = false
        var braceDepth = 0

        func flush(asCode: Bool) {
            let joined = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                blocks.append(DiscussionBlock(isCode: asCode, text: joined))
            }
            currentLines.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flush(asCode: inFenced || inDef)
                inFenced.toggle()
                inDef = false
                continue
            }
            if inFenced {
                currentLines.append(line)
                continue
            }
            if !inDef && LSPHoverBodyParser.isDefinitionCode(trimmed) {
                flush(asCode: false)
                inDef = true
                braceDepth = 0
            }
            currentLines.append(line)
            if inDef {
                braceDepth += lineBraceDelta(line)
                if braceDepth <= 0 && isStatementTerminated(trimmed) {
                    flush(asCode: true)
                    inDef = false
                }
            }
        }
        flush(asCode: inFenced || inDef)
        return blocks
    }

    private static func lineBraceDelta(_ line: String) -> Int {
        var delta = 0
        for char in line {
            if char == "{" {
                delta += 1
            } else if char == "}" {
                delta -= 1
            }
        }
        return delta
    }

    private static func isStatementTerminated(_ trimmed: String) -> Bool {
        trimmed.hasSuffix(";") || trimmed.hasSuffix("}") || trimmed.hasSuffix("{}")
    }
}
