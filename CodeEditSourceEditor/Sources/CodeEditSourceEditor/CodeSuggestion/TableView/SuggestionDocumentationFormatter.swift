//
//  SuggestionDocumentationFormatter.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit Contributors on 9/27/26.
//

import AppKit

/// One rendered piece of completion documentation, top to bottom.
enum SuggestionDocBlock {
    /// Prose with inline code, headings, and emphasis already styled.
    case prose(NSAttributedString)
    /// A fenced code block with syntax colors.
    case code(NSAttributedString)
}

/// Turns completion markdown into highlighted, top-to-bottom blocks.
enum SuggestionDocumentationFormatter {
    /// Renders markdown documentation. Backticks are removed and code is highlighted.
    static func blocks(markdown: String, font: NSFont, theme: EditorTheme?) -> [SuggestionDocBlock] {
        let palette = SuggestionDocPalette(theme: theme)
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var blocks: [SuggestionDocBlock] = []
        var prose: [String] = []
        var index = 0

        func flushProse() {
            let text = prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            prose.removeAll()
            guard !text.isEmpty else { return }
            blocks.append(.prose(renderProse(text, font: font, palette: palette)))
        }

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flushProse()
                index += 1
                var codeLines: [String] = []
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count {
                    index += 1
                }
                let code = codeLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !code.isEmpty {
                    blocks.append(.code(SuggestionCodeHighlighter.highlight(code, font: font, palette: palette)))
                }
                continue
            }
            if !isDivider(trimmed) {
                prose.append(lines[index])
            }
            index += 1
        }
        flushProse()
        return blocks
    }

    // MARK: - Prose

    private static func renderProse(
        _ text: String,
        font: NSFont,
        palette: SuggestionDocPalette
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 4
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = .left

        let result = NSMutableAttributedString()
        let lines = text.components(separatedBy: "\n")
        for (lineIndex, line) in lines.enumerated() {
            if lineIndex > 0 {
                result.append(NSAttributedString(string: "\n", attributes: baseAttributes(
                    font: font, color: palette.text, paragraph: paragraph
                )))
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                continue
            }
            if let heading = headingText(trimmed) {
                result.append(renderInline(
                    heading,
                    font: NSFont.systemFont(ofSize: font.pointSize, weight: .semibold),
                    palette: palette,
                    paragraph: paragraph,
                    forceBold: true
                ))
            } else if let bullet = bulletText(trimmed) {
                let prefix = NSAttributedString(string: "• ", attributes: baseAttributes(
                    font: NSFont.systemFont(ofSize: font.pointSize, weight: .semibold),
                    color: palette.comment,
                    paragraph: paragraph
                ))
                result.append(prefix)
                result.append(renderInline(
                    bullet, font: font, palette: palette, paragraph: paragraph, forceBold: false
                ))
            } else {
                result.append(renderInline(line, font: font, palette: palette, paragraph: paragraph, forceBold: false))
            }
        }
        return result
    }

    private static func headingText(_ trimmed: String) -> String? {
        var count = 0
        for character in trimmed {
            if character == "#" {
                count += 1
            } else {
                break
            }
        }
        guard (1...6).contains(count) else { return nil }
        let rest = trimmed.dropFirst(count)
        guard rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private static func bulletText(_ trimmed: String) -> String? {
        guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") else {
            return nil
        }
        let text = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private static func isDivider(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        return trimmed.allSatisfy { $0 == "-" || $0 == "*" || $0 == "_" }
    }

    private static func renderInline(
        _ text: String,
        font: NSFont,
        palette: SuggestionDocPalette,
        paragraph: NSParagraphStyle,
        forceBold: Bool
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let characters = Array(text)
        var index = 0
        var buffer = ""

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            let face = forceBold ? NSFont.systemFont(ofSize: font.pointSize, weight: .semibold) : font
            result.append(NSAttributedString(string: buffer, attributes: baseAttributes(
                font: face, color: palette.text, paragraph: paragraph
            )))
            buffer.removeAll(keepingCapacity: true)
        }

        while index < characters.count {
            if characters[index] == "`" {
                flushBuffer()
                let code = readDelimited(characters, from: &index, open: "`", close: "`")
                result.append(inlineCode(code, font: font, palette: palette, paragraph: paragraph))
                continue
            }
            if characters[index] == "*", index + 1 < characters.count, characters[index + 1] == "*" {
                flushBuffer()
                let bold = readDelimited(characters, from: &index, open: "**", close: "**")
                let boldFont = NSFont.systemFont(ofSize: font.pointSize, weight: .semibold)
                result.append(renderInline(
                    bold, font: boldFont, palette: palette, paragraph: paragraph, forceBold: true
                ))
                continue
            }
            if characters[index] == "[", let link = consumeLink(characters, from: index) {
                flushBuffer()
                result.append(NSAttributedString(string: link.label, attributes: baseAttributes(
                    font: font, color: palette.function, paragraph: paragraph
                )))
                index = link.next
                continue
            }
            buffer.append(characters[index])
            index += 1
        }
        flushBuffer()
        return result
    }

    private static func consumeLink(
        _ characters: [Character],
        from start: Int
    ) -> (label: String, next: Int)? {
        var index = start + 1
        var label = ""
        while index < characters.count && characters[index] != "]" {
            label.append(characters[index])
            index += 1
        }
        guard index + 1 < characters.count, characters[index] == "]", characters[index + 1] == "(" else {
            return nil
        }
        index += 2
        while index < characters.count && characters[index] != ")" {
            index += 1
        }
        guard index < characters.count else { return nil }
        return (label, index + 1)
    }

    private static func readDelimited(
        _ characters: [Character],
        from index: inout Int,
        open: String,
        close: String
    ) -> String {
        index += open.count
        var text = ""
        let end = Array(close)
        while index < characters.count {
            if characters[index..<min(index + end.count, characters.count)].elementsEqual(end) {
                index += end.count
                break
            }
            text.append(characters[index])
            index += 1
        }
        return text
    }

    private static func inlineCode(
        _ code: String,
        font: NSFont,
        palette: SuggestionDocPalette,
        paragraph: NSParagraphStyle
    ) -> NSAttributedString {
        let mono = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .medium)
        let color = inlineCodeColor(code, palette: palette)
        return NSAttributedString(string: code, attributes: [
            .font: mono,
            .foregroundColor: color,
            .backgroundColor: NSColor.labelColor.withAlphaComponent(0.10),
            .paragraphStyle: paragraph
        ])
    }

    private static func inlineCodeColor(_ code: String, palette: SuggestionDocPalette) -> NSColor {
        let lowered = code.lowercased()
        if code.contains("/") || lowered.hasSuffix(".h") || lowered.hasSuffix(".hpp")
            || lowered.hasSuffix(".swift") || lowered.hasSuffix(".cpp") || lowered.hasSuffix(".c") {
            return palette.string
        }
        if code.first?.isUppercase == true {
            return palette.type
        }
        return palette.variable
    }

    private static func baseAttributes(
        font: NSFont,
        color: NSColor,
        paragraph: NSParagraphStyle
    ) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }
}
