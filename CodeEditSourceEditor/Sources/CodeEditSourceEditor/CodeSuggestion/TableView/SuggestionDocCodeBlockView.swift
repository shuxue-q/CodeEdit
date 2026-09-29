//
//  SuggestionDocCodeBlockView.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit Contributors on 9/27/26.
//

import AppKit

/// Clip view whose origin is the top, so documentation lays out downward.
final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

/// Rounded card around a highlighted code block.
final class SuggestionDocCodeBlockView: NSView {
    private let inset: CGFloat = 8
    private let label = NSTextField(wrappingLabelWithString: "")

    var preferredTextWidth: CGFloat = 0 {
        didSet { invalidateIntrinsicContentSize() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.isBordered = false
        label.drawsBackground = false
        label.backgroundColor = .clear
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        (label.cell as? NSTextFieldCell)?.wraps = true
        (label.cell as? NSTextFieldCell)?.isScrollable = false
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset)
        ])
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        refreshBackground()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setAttributedString(_ string: NSAttributedString) {
        label.attributedStringValue = string
        invalidateIntrinsicContentSize()
    }

    func measuredHeight(forWidth width: CGFloat) -> CGFloat {
        let textWidth = max(1, width - inset * 2)
        label.preferredMaxLayoutWidth = textWidth
        let bounds = NSRect(x: 0, y: 0, width: textWidth, height: 10_000)
        let size = label.cell?.cellSize(forBounds: bounds) ?? .zero
        return ceil(size.height) + inset * 2
    }

    func refreshBackground() {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshBackground()
    }

    override var intrinsicContentSize: NSSize {
        let width = preferredTextWidth > 1 ? preferredTextWidth : bounds.width
        let height = width > 1 ? measuredHeight(forWidth: width) : 0
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }
}

/// Sums the wrapped height of documentation views.
enum SuggestionPreviewMeasure {
    static func height(of views: [NSView], spacing: CGFloat, width: CGFloat) -> CGFloat {
        guard !views.isEmpty else { return 0 }
        var total = views.reduce(CGFloat(0)) { $0 + height(of: $1, width: width) }
        if views.count > 1 {
            total += spacing * CGFloat(views.count - 1)
        }
        return total
    }

    private static func height(of view: NSView, width: CGFloat) -> CGFloat {
        if let code = view as? SuggestionDocCodeBlockView {
            return code.measuredHeight(forWidth: width)
        }
        guard let label = view as? NSTextField else {
            let intrinsic = view.intrinsicContentSize.height
            return intrinsic > 0 ? intrinsic : 0
        }
        let bounds = NSRect(x: 0, y: 0, width: max(1, width), height: 10_000)
        let size = label.cell?.cellSize(forBounds: bounds) ?? .zero
        return ceil(max(size.height, 0))
    }
}
