//
//  LSPHoverView.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/10/26.
//

import AppKit
import CodeEditLanguages
import SwiftUI

/// Preference key to measure the hover view's dynamic content height.
private struct HoverContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Renders language-server hover documentation inside a styled popover.
///
/// Features formatted declaration headers with smart line breaking, syntax highlighting
/// matching the active editor theme, bold section titles and parameter badges,
/// callout cards, and inline markdown styling.
struct LSPHoverView: View {
    static let popoverWidth: CGFloat = 460
    static let minHeight: CGFloat = 40
    static let maxHeight: CGFloat = 340

    @ObservedObject var themeModel: ThemeModel = .shared

    /// The original raw hover content from the language server.
    let content: String
    /// Optional code language of the document.
    let language: CodeLanguage?

    let documentation: LSPHoverDocumentation

    var onHeightChange: ((CGFloat) -> Void)?

    @State private var measuredHeight: CGFloat = 0

    init(content: String, language: CodeLanguage? = nil, onHeightChange: ((CGFloat) -> Void)? = nil) {
        self.content = content
        self.language = language
        self.onHeightChange = onHeightChange
        self.documentation = LSPHoverParser.parse(
            content: content,
            fallbackLanguage: language?.id.rawValue
        )
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                if let declaration = documentation.declaration {
                    declarationSection(declaration)
                }

                if let summary = documentation.summary, !summary.isEmpty {
                    summarySection(summary)
                }

                if !documentation.parameters.isEmpty {
                    parametersSection(documentation.parameters)
                }

                if let returns = documentation.returns, !returns.isEmpty {
                    returnsSection(returns)
                }

                if let throwsDesc = documentation.throwsDescription, !throwsDesc.isEmpty {
                    throwsSection(throwsDesc)
                }

                if !documentation.callouts.isEmpty {
                    calloutsSection(documentation.callouts)
                }

                if let discussion = documentation.discussion, !discussion.isEmpty {
                    discussionSection(discussion)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: HoverContentHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .onPreferenceChange(HoverContentHeightKey.self) { newHeight in
            measuredHeight = newHeight
            onHeightChange?(newHeight)
        }
        .frame(width: Self.popoverWidth, height: targetHeight)
    }

    private var targetHeight: CGFloat {
        if measuredHeight > 0 {
            return min(max(measuredHeight, Self.minHeight), Self.maxHeight)
        }
        return min(max(documentation.estimatedHeight, Self.minHeight), Self.maxHeight)
    }

    // MARK: - Sections

    private func declarationSection(_ declaration: LSPHoverDeclaration) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let kind = declaration.kind {
                HStack(spacing: 5) {
                    Image(systemName: kind.iconName)
                        .foregroundColor(kind.tintColor)
                        .font(.system(size: 11, weight: .semibold))
                    Text(kind.title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    if let lang = declaration.language, !lang.isEmpty {
                        Text("•")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text(lang)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Text(LSPCodeHighlighter.highlight(
                code: declaration.code,
                symbolName: declaration.symbolName,
                theme: themeModel.selectedTheme?.editor
            ))
            .textSelection(.enabled)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private func summarySection(_ summary: String) -> some View {
        Text(LSPCodeHighlighter.highlightInlineMarkdown(
            text: summary,
            theme: themeModel.selectedTheme?.editor
        ))
        .textSelection(.enabled)
        .font(.system(size: 12))
        .foregroundColor(.primary)
        .lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func parametersSection(_ parameters: [LSPHoverParameter]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "list.bullet")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11, weight: .semibold))
                Text("Parameters")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(parameters) { param in
                    parameterRow(param)
                }
            }
        }
    }

    private func parameterRow(_ param: LSPHoverParameter) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 6) {
                Text(param.name)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(4)

                if let type = param.type {
                    Text(type)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(
                            themeModel.selectedTheme?.editor.types.swiftColor ?? Color(nsColor: .systemTeal)
                        )
                }
            }

            if !param.description.isEmpty {
                Text(LSPCodeHighlighter.highlightInlineMarkdown(
                    text: param.description,
                    theme: themeModel.selectedTheme?.editor
                ))
                .textSelection(.enabled)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 4)
            }
        }
    }
}

// MARK: - Supplementary Sections Extension

extension LSPHoverView {
    func returnsSection(_ returns: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 11, weight: .semibold))
                Text("Returns")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }

            Text(LSPCodeHighlighter.highlightInlineMarkdown(
                text: returns,
                theme: themeModel.selectedTheme?.editor
            ))
            .textSelection(.enabled)
            .font(.system(size: 12))
            .foregroundColor(.primary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    func throwsSection(_ throwsDesc: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 11, weight: .semibold))
                Text("Throws")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }

            Text(LSPCodeHighlighter.highlightInlineMarkdown(
                text: throwsDesc,
                theme: themeModel.selectedTheme?.editor
            ))
            .textSelection(.enabled)
            .font(.system(size: 12))
            .foregroundColor(.primary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    func calloutsSection(_ callouts: [LSPHoverCallout]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(callouts) { callout in
                calloutCard(callout)
            }
        }
    }

    func calloutCard(_ callout: LSPHoverCallout) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: callout.iconName)
                .foregroundColor(callout.tintColor)
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(callout.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(callout.tintColor)

                Text(LSPCodeHighlighter.highlightInlineMarkdown(
                    text: callout.message,
                    theme: themeModel.selectedTheme?.editor
                ))
                .textSelection(.enabled)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(callout.tintColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(callout.tintColor.opacity(0.25), lineWidth: 1)
        )
        .textSelection(.enabled)
    }
}
