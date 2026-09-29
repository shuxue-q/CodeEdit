//
//  SuggestionPathFormatter.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit Contributors on 9/27/26.
//

import AppKit

/// File path shown at the end of a suggestion's documentation.
enum SuggestionPathFormatter {
    static func string(components: [String], target: CursorPosition?, font: NSFont) -> NSAttributedString {
        let folder = NSTextAttachment()
        folder.image = symbol("folder.fill", pointSize: font.pointSize, color: .systemBlue)
        let string = NSMutableAttributedString(attachment: folder)
        string.append(NSAttributedString(string: " "))

        for (idx, component) in components.enumerated() {
            string.append(NSAttributedString(string: component, attributes: [.foregroundColor: NSColor.labelColor]))
            if idx != components.count - 1 {
                string.append(NSAttributedString(string: " "))
                let separator = NSTextAttachment()
                separator.image = symbol("chevron.compact.right", pointSize: font.pointSize + 1, color: .labelColor)
                string.append(NSAttributedString(attachment: separator))
                string.append(NSAttributedString(string: " "))
            }
        }

        if let target {
            string.append(NSAttributedString(string: ":\(target.start.line)"))
            if target.start.column > 1 {
                string.append(NSAttributedString(string: ":\(target.start.column)"))
            }
        }
        if let paragraph = NSMutableParagraphStyle.default.mutableCopy() as? NSMutableParagraphStyle {
            paragraph.lineBreakMode = .byTruncatingMiddle
            string.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: string.length))
        }
        return string
    }

    private static func symbol(_ name: String, pointSize: CGFloat, color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(paletteColors: [color])
            .applying(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }
}
