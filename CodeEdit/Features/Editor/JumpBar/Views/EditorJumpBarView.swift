//
//  EditorJumpBarView.swift
//  CodeEdit
//
//  Created by Lukas Pistrol on 17.03.22.
//

import SwiftUI

struct EditorJumpBarView: View {
    private let file: CEWorkspaceFile?
    private let shouldShowTabBar: Bool
    private let tappedOpenFile: (CEWorkspaceFile) -> Void

    @Environment(\.colorScheme)
    private var colorScheme

    @Environment(\.isActiveEditor)
    private var isActiveEditor

    @Environment(\.controlActiveState)
    private var activeState

    @Binding var codeFile: CodeFileDocument?

    @EnvironmentObject private var editor: Editor

    @StateObject private var symbolModel = EditorJumpBarSymbolModel()

    static let height = 28.0

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var isTruncated: Bool = false
    @State private var crumbWidth: CGFloat?
    @State private var firstCrumbWidth: CGFloat?

    init(
        file: CEWorkspaceFile?,
        shouldShowTabBar: Bool,
        codeFile: Binding<CodeFileDocument?>,
        tappedOpenFile: @escaping (CEWorkspaceFile) -> Void
    ) {
        self.file = file ?? nil
        self.shouldShowTabBar = shouldShowTabBar
        self._codeFile = codeFile
        self.tappedOpenFile = tappedOpenFile
    }

    var fileItems: [CEWorkspaceFile] {
        var treePath: [CEWorkspaceFile] = []
        var currentFile: CEWorkspaceFile? = file

        while let currentFileLoop = currentFile {
            treePath.insert(currentFileLoop, at: 0)
            currentFile = currentFileLoop.parent
        }

        return treePath
    }

    var body: some View {
        HStack(spacing: 0) {
            EditorJumpBarRelatedItemsButton(file: file, tappedOpenFile: tappedOpenFile)
                .padding(.leading, 6)

            jumpBarDivider

            crumbs
                .frame(maxWidth: .infinity)

            EditorJumpBarIssueControls()
                .padding(.trailing, 6)
        }
        .safeAreaInset(edge: .leading, spacing: 0) {
            if !shouldShowTabBar {
                EditorTabBarLeadingAccessories()
            }
        }
        .safeAreaInset(edge: .trailing, spacing: 0) {
            if !shouldShowTabBar {
                EditorTabBarTrailingAccessories(codeFile: $codeFile)
            }
        }
        .frame(height: Self.height, alignment: .center)
        .opacity(activeState == .inactive ? 0.8 : 1.0)
        .grayscale(isActiveEditor ? 0.0 : 1.0)
        .onAppear {
            symbolModel.load(file: file)
            symbolModel.cursorMoved(editor.selectedTab?.cursorPositions.first)
        }
        .onChange(of: file) { _, newFile in
            symbolModel.load(file: newFile)
        }
        .onChange(of: editor.selectedTab?.cursorPositions) { _, newValue in
            symbolModel.cursorMoved(newValue?.first)
        }
    }

    private var jumpBarDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.18))
            .frame(width: 1, height: 12)
            .padding(.horizontal, 4)
    }

    private var crumbs: some View {
        GeometryReader { containerProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    if file == nil {
                        Text("No Selection")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(
                                activeState != .inactive
                                ? isActiveEditor ? .primary : .secondary
                                : Color(nsColor: .tertiaryLabelColor)
                            )
                            .frame(maxHeight: .infinity)
                    } else {
                        ForEach(fileItems, id: \.self) { fileItem in
                            EditorJumpBarComponent(
                                fileItem: fileItem,
                                tappedOpenFile: tappedOpenFile,
                                isLastItem: false,
                                isTruncated: fileItems.first == fileItem ? $firstCrumbWidth : $crumbWidth
                            )
                        }
                        if let tab = editor.selectedTab {
                            EditorJumpBarSymbolComponent(
                                model: symbolModel,
                                editorInstance: tab
                            )
                        }
                    }
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                if crumbWidth == nil {
                                    textWidth = proxy.size.width
                                }
                            }
                            .onChange(of: proxy.size.width) { _, newValue in
                                if crumbWidth == nil {
                                    textWidth = newValue
                                }
                            }
                    }
                )
            }
            .onAppear {
                containerWidth = containerProxy.size.width
            }
            .onChange(of: containerProxy.size.width) { _, newValue in
                containerWidth = newValue
            }
            .onChange(of: textWidth) { _, _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    resize()
                }
            }
            .onChange(of: containerWidth) { _, _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    resize()
                }
            }
        }
    }

    private func resize() {
        let minWidth: CGFloat = 20
        let snapThreshold: CGFloat = 30
        let maxWidth: CGFloat = textWidth / CGFloat(fileItems.count)
        let exponent: CGFloat = 5.0
        var betweenWidth: CGFloat = 0.0

        if textWidth >= containerWidth {
            let scale = max(0, min(1, containerWidth / textWidth))
            betweenWidth = floor((minWidth + (maxWidth - minWidth) * pow(scale, exponent)))
            if betweenWidth < snapThreshold {
                betweenWidth = minWidth
            }
            crumbWidth = betweenWidth
        } else {
            crumbWidth = nil
        }

        if betweenWidth > snapThreshold || crumbWidth == nil {
            firstCrumbWidth = nil
        } else {
            let otherCrumbs = CGFloat(max(fileItems.count - 1, 1))
            let usedWidth = otherCrumbs * snapThreshold

            // Multiplier to reserve extra space for other crumbs in the jump bar.
            // Increasing this value causes the first crumb to truncate sooner.
            let crumbSpacingMultiplier: CGFloat = 1.5
            let availableForFirst = containerWidth - usedWidth * crumbSpacingMultiplier
            if availableForFirst < snapThreshold {
                firstCrumbWidth = minWidth
            } else {
                firstCrumbWidth = availableForFirst
            }
        }
    }
}
