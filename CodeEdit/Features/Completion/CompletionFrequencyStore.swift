//
//  CompletionFrequencyStore.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import Foundation

/// Records how often completions are accepted, so the ranker can lift items the user picks often.
protocol CompletionFrequencyStoring: AnyObject {
    /// The `[normalizedLabel: count]` map for `languageId`.
    func frequencies(for languageId: String) -> [String: Int]
    /// Records that `label` was accepted for `languageId`.
    func recordAcceptance(label: String, languageId: String)
}

/// A per-language `[normalizedLabel: count]` store, persisted as JSON with decay once a language's
/// total count grows large, so the file stays bounded.
final class CompletionFrequencyStore: CompletionFrequencyStoring {
    /// The app-wide store, persisted alongside settings.
    static let shared = CompletionFrequencyStore()

    /// Counts are scaled down once a language's total exceeds this, to keep the store bounded.
    static let decayThreshold = 1_000
    /// The factor counts are multiplied by when decaying.
    static let decayFactor = 0.95
    /// How long to wait after a change before writing to disk.
    static let saveDelay: TimeInterval = 2

    private var storage: [String: [String: Int]]
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.codeedit.completionFrequencyStore")
    private var saveWorkItem: DispatchWorkItem?

    /// Creates a store backed by `fileURL`, or the default location under Application Support.
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.storage = Self.load(from: self.fileURL)
    }

    /// The default persistence location: `~/Library/Application Support/CodeEdit/completion-frequency.json`.
    static var defaultFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("CodeEdit", isDirectory: true)
            .appendingPathComponent("completion-frequency.json")
    }

    func frequencies(for languageId: String) -> [String: Int] {
        queue.sync { storage[languageId] ?? [:] }
    }

    func recordAcceptance(label: String, languageId: String) {
        let key = CompletionDeduplicator.normalizedLabel(label)
        guard !key.isEmpty else { return }
        queue.sync {
            var languageStorage = storage[languageId] ?? [:]
            languageStorage[key, default: 0] += 1
            decayIfNeeded(&languageStorage)
            storage[languageId] = languageStorage
        }
        scheduleSave()
    }

    private func decayIfNeeded(_ languageStorage: inout [String: Int]) {
        let total = languageStorage.values.reduce(0, +)
        guard total > Self.decayThreshold else { return }
        for key in languageStorage.keys {
            languageStorage[key] = Int(Double(languageStorage[key] ?? 0) * Self.decayFactor)
        }
    }

    private static func load(from fileURL: URL) -> [String: [String: Int]] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: workItem)
    }

    private func save() {
        let snapshot = queue.sync { storage }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// An in-memory frequency store, for tests that should not touch disk.
final class InMemoryCompletionFrequencyStore: CompletionFrequencyStoring {
    private(set) var storage: [String: [String: Int]] = [:]

    func frequencies(for languageId: String) -> [String: Int] {
        storage[languageId] ?? [:]
    }

    func recordAcceptance(label: String, languageId: String) {
        let key = CompletionDeduplicator.normalizedLabel(label)
        guard !key.isEmpty else { return }
        var languageStorage = storage[languageId] ?? [:]
        languageStorage[key, default: 0] += 1
        storage[languageId] = languageStorage
    }
}
