//
//  LSPCodeHighlighter.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/16/26.
//

import AppKit
import Foundation
import SwiftUI

/// Provides syntax highlighting for hover signatures, code blocks, and inline documentation text.
enum LSPCodeHighlighter {
    /// Token classifications for syntax coloring.
    enum TokenKind: Equatable {
        case keyword
        case type
        case symbolName
        case functionName
        case value
        case attribute
        case string
        case number
        case comment
        case punctuation
        case plain
    }

    /// A tokenized segment of code.
    struct Token: Equatable {
        var text: String
        var kind: TokenKind
    }

    /// Highlights code into an ``AttributedString`` using editor theme colors.
    static func highlight(
        code: String,
        symbolName: String? = nil,
        theme: Theme.EditorColors?
    ) -> AttributedString {
        let tokens = tokenize(code: code, symbolName: symbolName)
        var result = AttributedString()

        for token in tokens {
            var run = AttributedString(token.text)
            run.font = font(for: token.kind)
            run.foregroundColor = color(for: token.kind, theme: theme)
            result.append(run)
        }

        return result
    }

    /// Highlights markdown text with line-break preservation, code pills, and comment/definition coloring.
    static func highlightInlineMarkdown(text: String, theme: Theme.EditorColors?) -> AttributedString {
        guard !text.isEmpty else { return AttributedString() }

        // Normalize dividers first so divider sequences become distinct lines
        let normalized = LSPHoverParser.normalizeDividers(text)
        let lines = normalized.components(separatedBy: "\n")
        var lineAttributed: [AttributedString] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if let last = lineAttributed.last, !String(last.characters).isEmpty {
                    lineAttributed.append(AttributedString(""))
                }
                continue
            }

            if LSPHoverParser.isDividerLine(trimmed) {
                continue
            }

            if isCommentLine(trimmed) {
                lineAttributed.append(highlight(code: line, theme: theme))
            } else if isDefinitionLine(trimmed) {
                lineAttributed.append(highlight(code: line, theme: theme))
            } else {
                lineAttributed.append(highlightMarkdownLine(line, theme: theme))
            }
        }

        var result = AttributedString()
        for (index, item) in lineAttributed.enumerated() {
            if index > 0 {
                result.append(AttributedString("\n"))
            }
            result.append(item)
        }
        return result
    }

    private static func isCommentLine(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("//") || trimmed.hasPrefix("/*")
            || trimmed.hasPrefix("///") || trimmed.hasPrefix("//!") || trimmed.hasSuffix("*/")
    }

    private static func isDefinitionLine(_ trimmed: String) -> Bool {
        LSPHoverBodyParser.isDefinitionCode(trimmed)
    }

    private static func highlightMarkdownLine(_ line: String, theme: Theme.EditorColors?) -> AttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if let heading = formatHeading(trimmed, theme: theme) {
            return heading
        }

        if isBulletListItem(trimmed) {
            return formatBulletItem(trimmed, theme: theme)
        }

        if let numbered = formatNumberedItem(trimmed, theme: theme) {
            return numbered
        }

        if let labeled = formatDocLabel(trimmed, theme: theme) {
            return labeled
        }

        return formatInlineMarkdown(line, theme: theme)
    }

    private static func formatHeading(_ trimmed: String, theme: Theme.EditorColors?) -> AttributedString? {
        guard trimmed.hasPrefix("#") else { return nil }
        var count = 0
        for char in trimmed {
            if char == "#" {
                count += 1
            } else {
                break
            }
        }
        guard count >= 1 && count <= 6 else { return nil }
        let afterHashes = trimmed.dropFirst(count)
        guard afterHashes.hasPrefix(" ") else { return nil }
        let headingText = afterHashes.trimmingCharacters(in: .whitespaces)
        guard !headingText.isEmpty else { return nil }

        let fontSize: CGFloat = count <= 2 ? 13.0 : (count <= 4 ? 12.0 : 11.5)
        var attributed = formatInlineMarkdown(headingText, theme: theme)
        for run in attributed.runs {
            attributed[run.range].font = .system(size: fontSize, weight: .bold)
            attributed[run.range].foregroundColor = theme?.text.swiftColor ?? Color.primary
        }
        return attributed
    }

    private static func isBulletListItem(_ trimmed: String) -> Bool {
        (trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ "))
            && !LSPHoverParser.isDividerLine(trimmed)
    }

    private static func formatBulletItem(_ trimmed: String, theme: Theme.EditorColors?) -> AttributedString {
        let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        var bullet = AttributedString("  • ")
        bullet.font = .system(size: 12, weight: .bold)
        bullet.foregroundColor = Color.secondary
        if let labeled = formatDocLabel(content, theme: theme) {
            bullet.append(labeled)
        } else {
            bullet.append(formatInlineMarkdown(content, theme: theme))
        }
        return bullet
    }

    private static func formatNumberedItem(_ trimmed: String, theme: Theme.EditorColors?) -> AttributedString? {
        guard let dotIndex = trimmed.firstIndex(of: "."),
              trimmed.index(after: dotIndex) < trimmed.endIndex,
              trimmed[trimmed.index(after: dotIndex)] == " " else {
            return nil
        }
        let prefix = String(trimmed[..<dotIndex])
        guard Int(prefix) != nil else { return nil }
        let numberStr = String(trimmed[...dotIndex]) + " "
        let content = String(trimmed[trimmed.index(after: dotIndex)...]).trimmingCharacters(in: .whitespaces)

        var numAttributed = AttributedString("  " + numberStr)
        numAttributed.font = .system(size: 12, weight: .bold)
        numAttributed.foregroundColor = Color.secondary
        if let labeled = formatDocLabel(content, theme: theme) {
            numAttributed.append(labeled)
        } else {
            numAttributed.append(formatInlineMarkdown(content, theme: theme))
        }
        return numAttributed
    }

    private static let docLabels: [String] = [
        "Note:", "Warning:", "Important:", "Deprecated:", "Example:", "Examples:",
        "Usage:", "Discussion:", "Precondition:", "Postcondition:", "Requires:",
        "Complexity:", "See Also:", "Since:", "Version:", "Author:", "Default:",
        "Type:", "Details:", "Overview:"
    ]

    private static func formatDocLabel(_ trimmed: String, theme: Theme.EditorColors?) -> AttributedString? {
        for label in docLabels where trimmed.hasPrefix(label) {
            let remainder = trimmed.dropFirst(label.count).trimmingCharacters(in: .whitespaces)
            var labelAttributed = AttributedString(label)
            labelAttributed.font = .system(size: 12, weight: .bold)
            labelAttributed.foregroundColor = theme?.variables.swiftColor ?? Color.primary
            if !remainder.isEmpty {
                labelAttributed.append(AttributedString(" "))
                labelAttributed.append(formatInlineMarkdown(remainder, theme: theme))
            }
            return labelAttributed
        }
        return nil
    }

    private static func formatInlineMarkdown(_ text: String, theme: Theme.EditorColors?) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions(allowsExtendedAttributes: true)
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        guard let attributed = try? AttributedString(markdown: text, options: options) else {
            return AttributedString(text)
        }

        var result = AttributedString()
        for run in attributed.runs {
            var runSlice = AttributedString(attributed[run.range])
            if run.inlinePresentationIntent?.contains(.code) == true {
                let codeText = String(runSlice.characters)
                let codeTokens = tokenize(code: codeText)
                if codeTokens.count <= 1 {
                    runSlice.font = .system(size: 11.5, weight: .medium, design: .monospaced)
                    runSlice.backgroundColor = Color.secondary.opacity(0.12)
                    if let firstToken = codeTokens.first {
                        runSlice.foregroundColor = color(for: firstToken.kind, theme: theme)
                    } else {
                        runSlice.foregroundColor = theme?.variables.swiftColor ?? Color.primary
                    }
                    result.append(runSlice)
                } else {
                    for token in codeTokens {
                        var tokenRun = AttributedString(token.text)
                        tokenRun.inlinePresentationIntent = .code
                        tokenRun.font = .system(size: 11.5, weight: .medium, design: .monospaced)
                        tokenRun.backgroundColor = Color.secondary.opacity(0.12)
                        tokenRun.foregroundColor = color(for: token.kind, theme: theme)
                        result.append(tokenRun)
                    }
                }
            } else {
                result.append(runSlice)
            }
        }

        return result
    }

    // MARK: - Styling

    private static func font(for kind: TokenKind) -> SwiftUI.Font {
        switch kind {
        case .symbolName, .functionName: return .system(size: 12, weight: .bold, design: .monospaced)
        case .keyword, .value: return .system(size: 12, weight: .semibold, design: .monospaced)
        case .comment: return .system(size: 12, weight: .regular, design: .monospaced).italic()
        default: return .system(size: 12, weight: .regular, design: .monospaced)
        }
    }

    private static func color(for kind: TokenKind, theme: Theme.EditorColors?) -> SwiftUI.Color {
        switch kind {
        case .keyword: return theme?.keywords.swiftColor ?? Color(nsColor: .systemPurple)
        case .type: return theme?.types.swiftColor ?? Color(nsColor: .systemTeal)
        case .symbolName: return theme?.variables.swiftColor ?? Color.primary
        case .functionName: return theme?.commands.swiftColor ?? Color(nsColor: .systemBlue)
        case .value: return theme?.values.swiftColor ?? Color(nsColor: .systemIndigo)
        case .attribute: return theme?.attributes.swiftColor ?? Color(nsColor: .systemOrange)
        case .string: return theme?.strings.swiftColor ?? Color(nsColor: .systemRed)
        case .number: return theme?.numbers.swiftColor ?? Color(nsColor: .systemBlue)
        case .comment: return theme?.comments.swiftColor ?? Color(nsColor: .secondaryLabelColor)
        case .punctuation, .plain: return theme?.text.swiftColor ?? Color.primary
        }
    }
}
