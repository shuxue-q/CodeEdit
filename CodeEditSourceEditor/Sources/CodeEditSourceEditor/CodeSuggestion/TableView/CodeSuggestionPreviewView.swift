//
//  CodeSuggestionPreviewView.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 7/28/25.
//

import AppKit

/// Documentation panel shown to the right of the completion list.
///
/// Content is packed from the top downward. The panel scrolls when the document is taller
/// than the window, which is sized to the taller of the list and this panel.
final class CodeSuggestionPreviewView: NSVisualEffectView {
    private let spacing: CGFloat = 8
    static let horizontalInset: CGFloat = 13

    var sourcePreview: NSAttributedString? {
        didSet {
            sourcePreviewLabel.attributedStringValue = sourcePreview ?? NSAttributedString(string: "")
            sourcePreviewLabel.isHidden = sourcePreview == nil
            scrollContentToTop()
        }
    }

    var documentation: String? {
        didSet { renderDocumentation() }
    }

    var pathComponents: [String] = [] {
        didSet { configurePathComponentsLabel() }
    }

    var targetRange: CursorPosition? {
        didSet { configurePathComponentsLabel() }
    }

    var font: NSFont = .systemFont(ofSize: 12) {
        didSet {
            sourcePreviewLabel.font = font
            pathComponentsLabel.font = .systemFont(ofSize: font.pointSize)
            configurePathComponentsLabel()
        }
    }

    var documentationFont: NSFont = .systemFont(ofSize: 12) {
        didSet { renderDocumentation() }
    }

    var theme: EditorTheme? {
        didSet { renderDocumentation() }
    }

    private let stackView = NSStackView()
    private let scrollView = NSScrollView()
    private let dividerView = NSView()
    private let documentView = NSView()
    private let sourcePreviewLabel = NSTextField(wrappingLabelWithString: "")
    private let pathComponentsLabel = NSTextField(wrappingLabelWithString: "")
    private var documentationViews: [NSView] = []
    private var pendingScrollToTop = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureHierarchy()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func hideIfEmpty() {
        isHidden = sourcePreview == nil && (documentation?.isEmpty != false) && pathComponents.isEmpty
    }

    func setPreferredMaxLayoutWidth(width: CGFloat) {
        applyTextWidth(width)
    }

    /// Height the window needs in order to show this panel without clipping it.
    func contentHeight(forWidth width: CGFloat) -> CGFloat {
        let textWidth = max(1, width - 1 - Self.horizontalInset * 2)
        let content = measuredContentHeight(textWidth: textWidth)
        return content + SuggestionController.WINDOW_PADDING * 2
    }

    func scrollContentToTop() {
        pendingScrollToTop = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let didLayout = layoutDocument()
        guard pendingScrollToTop, didLayout else { return }
        pendingScrollToTop = false
        let clip = scrollView.contentView
        clip.scroll(to: .zero)
        scrollView.reflectScrolledClipView(clip)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        for case let block as SuggestionDocCodeBlockView in documentationViews {
            block.refreshBackground()
        }
    }

    // MARK: - Hierarchy

    private func configureHierarchy() {
        material = .windowBackground
        blendingMode = .behindWindow

        let clipView = FlippedClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.verticalScroller = NoSlotScroller()
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.documentView = documentView
        addSubview(scrollView)

        dividerView.translatesAutoresizingMaskIntoConstraints = false
        dividerView.wantsLayer = true
        dividerView.layer?.backgroundColor = NSColor.separatorColor.cgColor
        addSubview(dividerView)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .gravityAreas
        stackView.spacing = spacing
        stackView.detachesHiddenViews = true
        stackView.setHuggingPriority(.required, for: .vertical)
        documentView.addSubview(stackView)

        configureWrappingLabel(sourcePreviewLabel)
        configureWrappingLabel(pathComponentsLabel)
        pathComponentsLabel.maximumNumberOfLines = 1
        pathComponentsLabel.lineBreakMode = .byTruncatingMiddle
        pathComponentsLabel.usesSingleLineMode = true
        stackView.addView(sourcePreviewLabel, in: .top)
        stackView.addView(pathComponentsLabel, in: .top)
        pinWidth(of: sourcePreviewLabel, to: stackView)
        pinWidth(of: pathComponentsLabel, to: stackView)
        sourcePreviewLabel.isHidden = true
        pathComponentsLabel.isHidden = true
        installConstraints()
    }

    private func installConstraints() {
        let scrollLeading = scrollView.leadingAnchor.constraint(
            equalTo: dividerView.trailingAnchor,
            constant: Self.horizontalInset
        )
        scrollLeading.priority = .defaultHigh
        let scrollTrailing = scrollView.trailingAnchor.constraint(
            equalTo: trailingAnchor,
            constant: -Self.horizontalInset
        )
        scrollTrailing.priority = .defaultHigh
        // Content-sized stack pinned to the top. A required bottom pin would stretch it.
        let stackBottom = stackView.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor)
        stackBottom.priority = .defaultHigh

        NSLayoutConstraint.activate([
            dividerView.topAnchor.constraint(equalTo: topAnchor),
            dividerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            dividerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dividerView.widthAnchor.constraint(equalToConstant: 1),

            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: SuggestionController.WINDOW_PADDING),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -SuggestionController.WINDOW_PADDING),
            scrollLeading,
            scrollTrailing,

            stackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stackBottom
        ])
    }

    private func configureWrappingLabel(_ label: NSTextField) {
        label.isEditable = false
        // Selectable fields try to make this panel key and tear down ViewBridge.
        label.isSelectable = false
        label.isBezeled = false
        label.isBordered = false
        label.drawsBackground = false
        label.backgroundColor = .clear
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.usesSingleLineMode = false
        label.allowsDefaultTighteningForTruncation = false
        (label.cell as? NSTextFieldCell)?.wraps = true
        (label.cell as? NSTextFieldCell)?.isScrollable = false
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    // MARK: - Documentation

    private func renderDocumentation() {
        for view in documentationViews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        documentationViews.removeAll()

        let text = documentation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            let blocks = SuggestionDocumentationFormatter.blocks(
                markdown: text,
                font: documentationFont,
                theme: theme
            )
            let insertAt = stackView.views(in: .top).firstIndex(of: pathComponentsLabel) ?? 0
            for (offset, block) in blocks.enumerated() {
                let view = makeBlockView(block)
                documentationViews.append(view)
                stackView.insertView(view, at: insertAt + offset, in: .top)
                pinWidth(of: view, to: stackView)
            }
        }
        applyTextWidth(currentTextWidth())
        scrollContentToTop()
    }

    private func makeBlockView(_ block: SuggestionDocBlock) -> NSView {
        switch block {
        case .prose(let string):
            let label = NSTextField(wrappingLabelWithString: "")
            configureWrappingLabel(label)
            label.attributedStringValue = string
            return label
        case .code(let string):
            let view = SuggestionDocCodeBlockView()
            view.setAttributedString(string)
            return view
        }
    }

    private func configurePathComponentsLabel() {
        pathComponentsLabel.isHidden = pathComponents.isEmpty
        pathComponentsLabel.attributedStringValue = SuggestionPathFormatter.string(
            components: pathComponents,
            target: targetRange,
            font: font
        )
        scrollContentToTop()
    }

    // MARK: - Measurement

    private func currentTextWidth() -> CGFloat {
        let live = scrollView.contentView.bounds.width
        if live > 1 {
            return live
        }
        return max(1, SuggestionController.PREVIEW_WIDTH - 1 - Self.horizontalInset * 2)
    }

    private func applyTextWidth(_ width: CGFloat) {
        let textWidth = max(1, width)
        sourcePreviewLabel.preferredMaxLayoutWidth = textWidth
        pathComponentsLabel.preferredMaxLayoutWidth = textWidth
        for view in documentationViews {
            if let label = view as? NSTextField {
                label.preferredMaxLayoutWidth = textWidth
            } else if let code = view as? SuggestionDocCodeBlockView {
                code.preferredTextWidth = textWidth
            }
        }
    }

    private func measuredContentHeight(textWidth: CGFloat) -> CGFloat {
        applyTextWidth(textWidth)
        let views = stackView.views(in: .top).filter { !$0.isHidden }
        return SuggestionPreviewMeasure.height(of: views, spacing: spacing, width: textWidth)
    }

    @discardableResult
    private func layoutDocument() -> Bool {
        let width = scrollView.contentView.bounds.width
        guard width > 1 else { return false }
        applyTextWidth(width)
        let contentHeight = measuredContentHeight(textWidth: width)
        // At least as tall as the clip so short documents stay pinned to the top.
        let height = max(contentHeight, scrollView.contentView.bounds.height)
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        if documentView.frame.integral != frame.integral {
            documentView.frame = frame
        }
        return true
    }
}

private func pinWidth(of view: NSView, to stack: NSStackView) {
    let width = view.widthAnchor.constraint(equalTo: stack.widthAnchor)
    width.priority = .defaultHigh
    width.isActive = true
}
