//
//  EditorBookmarkManager.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit on 2024.
//

import Foundation

/// A bookmark representation in an editor document.
public struct EditorBookmark: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public let fileURL: URL
    public let fileName: String
    public let lineNumber: Int?
    public let lineContent: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        fileName: String,
        lineNumber: Int? = nil,
        lineContent: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fileURL = fileURL
        self.fileName = fileName
        self.lineNumber = lineNumber
        self.lineContent = lineContent
        self.createdAt = createdAt
    }
}

/// A manager for editor bookmarks.
public final class EditorBookmarkManager: ObservableObject {
    public static let shared = EditorBookmarkManager()

    @Published public private(set) var bookmarks: [EditorBookmark] = []

    private let userDefaultsKey = "CodeEdit.EditorBookmarks"

    public init() {
        loadBookmarks()
    }

    /// Adds a bookmark for the given file and optional line.
    public func addBookmark(
        fileURL: URL,
        fileName: String,
        lineNumber: Int?,
        lineContent: String?
    ) {
        let bookmark = EditorBookmark(
            fileURL: fileURL,
            fileName: fileName,
            lineNumber: lineNumber,
            lineContent: lineContent
        )
        bookmarks.append(bookmark)
        saveBookmarks()
    }

    /// Removes a bookmark by its unique identifier.
    public func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        saveBookmarks()
    }

    /// Clears all bookmarks.
    public func clearAll() {
        bookmarks.removeAll()
        saveBookmarks()
    }

    private func saveBookmarks() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    private func loadBookmarks() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([EditorBookmark].self, from: data) else {
            return
        }
        self.bookmarks = decoded
    }
}
