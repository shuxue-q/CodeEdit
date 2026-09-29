//
//  LSPSignatureHelpView.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/29/26.
//

import AppKit
import SwiftUI

/// The parameter-hint tooltip: the active signature with its current parameter in bold, the
/// overload position, and the parameter's documentation.
struct LSPSignatureHelpView: View {
    static let maxWidth: CGFloat = 640
    /// Space between the tooltip's edge and the signature text.
    static let horizontalPadding: CGFloat = 8

    let content: LSPSignatureHelpContent
    let font: NSFont

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                signatureText
                    .font(Font(font))
                    .fixedSize(horizontal: false, vertical: true)
                if content.signatureCount > 1 {
                    Text("\(content.signatureIndex + 1) of \(content.signatureCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            if let documentation = content.parameterDocumentation {
                Text(documentation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, 5)
        .frame(maxWidth: Self.maxWidth, alignment: .leading)
    }

    /// The signature with its active parameter emphasized.
    private var signatureText: Text {
        let label = content.label as NSString
        guard let range = content.activeParameterRange, range.max <= label.length else {
            return Text(content.label).foregroundColor(.primary)
        }
        let prefix = label.substring(to: range.location)
        let active = label.substring(with: range)
        let suffix = label.substring(from: range.max)
        let boldDescriptor = font.fontDescriptor.withSymbolicTraits(.bold)
        let boldFont = NSFont(descriptor: boldDescriptor, size: font.pointSize) ?? font
        return Text(prefix).foregroundColor(.secondary)
            + Text(active).font(Font(boldFont)).foregroundColor(.primary)
            + Text(suffix).foregroundColor(.secondary)
    }
}

/// A borderless window for the tooltip. It never becomes key, so typing stays in the editor.
final class LSPSignatureHelpWindow: NSPanel {
    private let hostingView: NSHostingView<LSPSignatureHelpView>

    init(content: LSPSignatureHelpContent, font: NSFont) {
        hostingView = NSHostingView(rootView: LSPSignatureHelpView(content: content, font: font))
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        hidesOnDeactivate = true
        level = .popUpMenu
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true

        let background = NSVisualEffectView()
        background.material = .toolTip
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 6
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 0.5
        background.layer?.borderColor = NSColor.separatorColor.cgColor

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: background.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: background.bottomAnchor)
        ])
        contentView = background
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows new content and resizes the window to fit it.
    func update(content: LSPSignatureHelpContent, font: NSFont) {
        hostingView.rootView = LSPSignatureHelpView(content: content, font: font)
        setContentSize(hostingView.fittingSize)
    }
}
