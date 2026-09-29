//
//  BookmarkNavigatorView.swift
//  CodeEdit
//
//  Created by CodeEdit on 22/09/2026.
//

import SwiftUI
import CodeEditSourceEditor

/// The Bookmarks navigator: an Xcode-style list of editor bookmarks grouped by file.
///
/// Bookmarks come from the shared ``EditorBookmarkManager`` in `CodeEditSourceEditor`
/// (they are added from the editor's context menu). Groups are sorted by file name,
/// file-level bookmarks appear before line bookmarks within a group, and tapping a
/// bookmark opens the file in the workspace editor at the bookmarked line.
struct BookmarkNavigatorView: View {
    @EnvironmentObject private var workspace: WorkspaceDocument
    @ObservedObject private var bookmarkManager = EditorBookmarkManager.shared

    @State private var filter: String = ""

    var body: some View {
        VStack(spacing: 0) {
            if bookmarkGroups.isEmpty {
                CEContentUnavailableView(
                    "No Bookmarks",
                    description: bookmarkManager.bookmarks.isEmpty
                        ? "Add a bookmark from the editor's context menu."
                        : "No bookmarks match the current filter.",
                    systemImage: "bookmark"
                )
            } else {
                bookmarkList
            }
            NavigatorFilterView(
                text: $filter,
                menu: { EmptyView() },
                leadingAccessories: {
                    Image(
                        systemName: filter.isEmpty
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill"
                    )
                    .foregroundStyle(
                        filter.isEmpty
                        ? Color(nsColor: .secondaryLabelColor)
                        : Color(nsColor: .controlAccentColor)
                    )
                    .padding(.leading, 4)
                    .help("Show bookmarks with matching text")
                },
                trailingAccessories: { EmptyView() }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu {
            Button("Clear All Bookmarks", role: .destructive) {
                bookmarkManager.clearAll()
            }
        }
    }

    private var bookmarkList: some View {
        List {
            ForEach(bookmarkGroups) { group in
                Section {
                    ForEach(group.bookmarks) { bookmark in
                        bookmarkRow(bookmark)
                    }
                } header: {
                    groupHeader(group)
                }
            }
        }
        .listStyle(.inset)
    }

    private func bookmarkRow(_ bookmark: EditorBookmark) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 11))
            Text(rowTitle(bookmark))
                .lineLimit(1)
            if let lineContent = bookmark.lineContent, !lineContent.isEmpty {
                Text(lineContent.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            open(bookmark)
        }
        .contextMenu {
            Button("Jump to Bookmark") {
                open(bookmark)
            }
            Divider()
            Button("Delete Bookmark", role: .destructive) {
                bookmarkManager.removeBookmark(id: bookmark.id)
            }
        }
        .accessibilityIdentifier("BookmarkEntry")
    }

    private func groupHeader(_ group: BookmarkFileGroup) -> some View {
        HStack(spacing: 6) {
            groupIcon(group)
            Text(group.fileName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .contextMenu {
            Button("Clear All Bookmarks", role: .destructive) {
                bookmarkManager.clearAll()
            }
        }
        .accessibilityIdentifier("BookmarkGroupHeader")
    }

    @ViewBuilder
    private func groupIcon(_ group: BookmarkFileGroup) -> some View {
        if let file = workspace.workspaceFileManager?.getFile(
            group.fileURL.path,
            createIfNotFound: true
        ) {
            Image(nsImage: file.nsIcon)
        } else {
            Image(systemName: FileIcon.fileIcon(fileType: nil))
        }
    }

    private func rowTitle(_ bookmark: EditorBookmark) -> String {
        if let lineNumber = bookmark.lineNumber {
            return "Line \(lineNumber)"
        }
        return bookmark.fileName
    }

    // MARK: - Grouping

    private struct BookmarkFileGroup: Identifiable {
        let fileURL: URL
        let fileName: String
        var bookmarks: [EditorBookmark]

        var id: URL { fileURL }
    }

    /// Bookmarks matching the current filter, grouped by file URL and sorted by file
    /// name. Within a group, file-level bookmarks (no line number) come first, then
    /// line bookmarks in ascending line order.
    private var bookmarkGroups: [BookmarkFileGroup] {
        Dictionary(grouping: filteredBookmarks, by: \.fileURL)
            .map { fileURL, bookmarks in
                BookmarkFileGroup(
                    fileURL: fileURL,
                    fileName: bookmarks.first?.fileName ?? fileURL.lastPathComponent,
                    bookmarks: bookmarks.sorted(by: isOrderedBefore)
                )
            }
            .sorted {
                $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending
            }
    }

    private var filteredBookmarks: [EditorBookmark] {
        guard !filter.isEmpty else { return bookmarkManager.bookmarks }
        return bookmarkManager.bookmarks.filter {
            $0.fileName.localizedCaseInsensitiveContains(filter)
                || ($0.lineContent?.localizedCaseInsensitiveContains(filter) ?? false)
        }
    }

    private func isOrderedBefore(_ lhs: EditorBookmark, _ rhs: EditorBookmark) -> Bool {
        switch (lhs.lineNumber, rhs.lineNumber) {
        case (nil, nil):
            return lhs.createdAt < rhs.createdAt
        case (nil, _):
            return true
        case (_, nil):
            return false
        case let (left?, right?):
            return left < right
        }
    }

    // MARK: - Navigation

    /// Opens the bookmarked file in the workspace editor and moves the cursor to the
    /// bookmarked line. Both `EditorBookmark.lineNumber` and ``CursorPosition`` are
    /// 1-indexed.
    private func open(_ bookmark: EditorBookmark) {
        guard let file = workspace.workspaceFileManager?.getFile(
            bookmark.fileURL.path,
            createIfNotFound: true
        ) else {
            return
        }
        workspace.editorManager?.openTab(item: file)
        workspace.editorManager?.activeEditor.selectedTab?.cursorPositions = [
            CursorPosition(line: max(bookmark.lineNumber ?? 1, 1), column: 1)
        ]
    }
}
