//
//  SnippetManager.swift
//  CodeEditSourceEditor
//
//  Created by CodeEdit on 2024.
//

import Foundation

/// A code snippet definition.
public struct CodeSnippet: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public let title: String
    public let summary: String
    public let shortcut: String
    public let code: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        summary: String = "",
        shortcut: String = "",
        code: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.shortcut = shortcut
        self.code = code
        self.createdAt = createdAt
    }
}

/// A manager for user code snippets.
public final class SnippetManager: ObservableObject {
    public static let shared = SnippetManager()

    @Published public private(set) var snippets: [CodeSnippet] = []

    private let userDefaultsKey = "CodeEdit.CodeSnippets"

    public init() {
        loadSnippets()
    }

    /// Adds a code snippet.
    public func addSnippet(_ snippet: CodeSnippet) {
        snippets.append(snippet)
        saveSnippets()
    }

    /// Removes a snippet by its unique identifier.
    public func removeSnippet(id: UUID) {
        snippets.removeAll { $0.id == id }
        saveSnippets()
    }

    private func saveSnippets() {
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    private func loadSnippets() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([CodeSnippet].self, from: data) else {
            return
        }
        self.snippets = decoded
    }
}
