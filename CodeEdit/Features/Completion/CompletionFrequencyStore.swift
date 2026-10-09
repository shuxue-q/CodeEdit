//
//  CompletionFrequencyStore.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import Foundation

/// What the ranker knows about past acceptances for one language and intent.
struct CompletionStatistics {
    /// `[normalizedLabel: count]` over every intent of the language: the original, coarser table.
    var languageFrequencies: [String: Int] = [:]
    /// `[normalizedLabel: count]` for the language and the intent the request is made in.
    var intentFrequencies: [String: Int] = [:]
    /// `[normalizedLabel: date]` of the last acceptance for the language and intent.
    var lastAccepted: [String: Date] = [:]
}

/// Records how often completions are accepted, so the ranker can lift items the user picks often.
protocol CompletionFrequencyStoring: AnyObject {
    /// The `[normalizedLabel: count]` map for `languageId`.
    func frequencies(for languageId: String) -> [String: Int]
    /// Records that `label` was accepted for `languageId`.
    func recordAcceptance(label: String, languageId: String)
    /// What is known about `languageId` and `intent`: counts, per-intent counts, and recency.
    func statistics(languageId: String, intent: CompletionIntent) -> CompletionStatistics
    /// Records that `label` was accepted at `date` for `languageId` while writing `intent`.
    func recordAcceptance(label: String, languageId: String, intent: CompletionIntent, at date: Date)
}

extension CompletionFrequencyStoring {
    func statistics(languageId: String, intent: CompletionIntent) -> CompletionStatistics {
        CompletionStatistics(languageFrequencies: frequencies(for: languageId))
    }

    func recordAcceptance(label: String, languageId: String, intent: CompletionIntent, at date: Date) {
        recordAcceptance(label: label, languageId: languageId)
    }
}

extension CompletionIntent {
    /// The stable name the intent is stored under.
    var storageKey: String { String(describing: self) }
}

/// A `[normalizedLabel: count]` store per language, plus per-intent counts and last-acceptance times,
/// persisted as JSON with decay once a language's total count grows large, so the files stay bounded.
///
/// The per-language table keeps its original file (`completion-frequency.json`) and format, so existing
/// data still loads. The per-intent counts and recency live next to it in `completion-statistics.json`.
final class CompletionFrequencyStore: CompletionFrequencyStoring {
    /// The app-wide store, persisted alongside settings.
    static let shared = CompletionFrequencyStore()

    /// Counts are scaled down once a language's total exceeds this, to keep the store bounded.
    static let decayThreshold = 1_000
    /// The factor counts are multiplied by when decaying.
    static let decayFactor = 0.95
    /// How long to wait after a change before writing to disk.
    static let saveDelay: TimeInterval = 2

    /// One label's acceptances in one language and intent.
    struct IntentEntry: Codable, Equatable {
        var count: Int
        /// The last acceptance, in seconds since the reference date.
        var last: TimeInterval
    }

    /// The per-intent file: `language → intent → label → entry`.
    private struct StatisticsFile: Codable {
        var version = 1
        var entries: [String: [String: [String: IntentEntry]]] = [:]
    }

    private var storage: [String: [String: Int]]
    private var intentStorage: [String: [String: [String: IntentEntry]]]
    private let fileURL: URL
    private let statisticsURL: URL
    private let queue = DispatchQueue(label: "com.codeedit.completionFrequencyStore")
    private var saveWorkItem: DispatchWorkItem?

    /// Creates a store backed by `fileURL`, or the default location under Application Support.
    /// The per-intent statistics are stored in `statisticsURL`, by default next to `fileURL`.
    init(fileURL: URL? = nil, statisticsURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.statisticsURL = statisticsURL ?? Self.siblingStatisticsURL(for: self.fileURL)
        self.storage = Self.load(from: self.fileURL)
        self.intentStorage = Self.loadStatistics(from: self.statisticsURL)
    }

    /// The default persistence location: `~/Library/Application Support/CodeEdit/completion-frequency.json`.
    static var defaultFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("CodeEdit", isDirectory: true)
            .appendingPathComponent("completion-frequency.json")
    }

    /// Where the per-intent statistics for a frequency file at `fileURL` live.
    static func siblingStatisticsURL(for fileURL: URL) -> URL {
        let name = fileURL.deletingPathExtension().lastPathComponent
        let sibling = name == "completion-frequency" ? "completion-statistics" : "\(name)-statistics"
        return fileURL.deletingLastPathComponent().appendingPathComponent(sibling).appendingPathExtension("json")
    }

    func frequencies(for languageId: String) -> [String: Int] {
        queue.sync { storage[languageId] ?? [:] }
    }

    func statistics(languageId: String, intent: CompletionIntent) -> CompletionStatistics {
        queue.sync {
            let entries = intentStorage[languageId]?[intent.storageKey] ?? [:]
            return CompletionStatistics(
                languageFrequencies: storage[languageId] ?? [:],
                intentFrequencies: entries.mapValues(\.count),
                lastAccepted: entries.mapValues { Date(timeIntervalSinceReferenceDate: $0.last) }
            )
        }
    }

    func recordAcceptance(label: String, languageId: String) {
        let key = CompletionDeduplicator.normalizedLabel(label)
        guard !key.isEmpty else { return }
        queue.sync { incrementLanguageCount(key: key, languageId: languageId) }
        scheduleSave()
    }

    func recordAcceptance(label: String, languageId: String, intent: CompletionIntent, at date: Date) {
        let key = CompletionDeduplicator.normalizedLabel(label)
        guard !key.isEmpty else { return }
        queue.sync {
            incrementLanguageCount(key: key, languageId: languageId)
            var intents = intentStorage[languageId] ?? [:]
            var entries = intents[intent.storageKey] ?? [:]
            var entry = entries[key] ?? IntentEntry(count: 0, last: 0)
            entry.count += 1
            entry.last = date.timeIntervalSinceReferenceDate
            entries[key] = entry
            intents[intent.storageKey] = entries
            decayIfNeeded(&intents)
            intentStorage[languageId] = intents
        }
        scheduleSave()
    }

    private func incrementLanguageCount(key: String, languageId: String) {
        var languageStorage = storage[languageId] ?? [:]
        languageStorage[key, default: 0] += 1
        decayIfNeeded(&languageStorage)
        storage[languageId] = languageStorage
    }

    private func decayIfNeeded(_ languageStorage: inout [String: Int]) {
        let total = languageStorage.values.reduce(0, +)
        guard total > Self.decayThreshold else { return }
        for key in languageStorage.keys {
            languageStorage[key] = Int(Double(languageStorage[key] ?? 0) * Self.decayFactor)
        }
    }

    /// Scales one language's per-intent counts down once their total is large, dropping emptied entries.
    private func decayIfNeeded(_ intents: inout [String: [String: IntentEntry]]) {
        let total = intents.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } }
        guard total > Self.decayThreshold else { return }
        for (intent, entries) in intents {
            var decayed = entries
            for (label, entry) in entries {
                let scaled = Int(Double(entry.count) * Self.decayFactor)
                decayed[label] = scaled >= 1 ? IntentEntry(count: scaled, last: entry.last) : nil
            }
            intents[intent] = decayed
        }
    }

    private static func load(from fileURL: URL) -> [String: [String: Int]] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func loadStatistics(from fileURL: URL) -> [String: [String: [String: IntentEntry]]] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(StatisticsFile.self, from: data) else {
            return [:]
        }
        return decoded.entries
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: workItem)
    }

    private func save() {
        let (languages, intents) = queue.sync { (storage, intentStorage) }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(languages) {
            try? data.write(to: fileURL, options: .atomic)
        }
        if let data = try? JSONEncoder().encode(StatisticsFile(entries: intents)) {
            try? data.write(to: statisticsURL, options: .atomic)
        }
    }
}

/// An in-memory frequency store, for tests that should not touch disk.
final class InMemoryCompletionFrequencyStore: CompletionFrequencyStoring {
    private(set) var storage: [String: [String: Int]] = [:]
    private var intentStorage: [String: [String: [String: (count: Int, last: Date)]]] = [:]

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

    func statistics(languageId: String, intent: CompletionIntent) -> CompletionStatistics {
        let entries = intentStorage[languageId]?[intent.storageKey] ?? [:]
        return CompletionStatistics(
            languageFrequencies: frequencies(for: languageId),
            intentFrequencies: entries.mapValues(\.count),
            lastAccepted: entries.mapValues(\.last)
        )
    }

    func recordAcceptance(label: String, languageId: String, intent: CompletionIntent, at date: Date) {
        let key = CompletionDeduplicator.normalizedLabel(label)
        guard !key.isEmpty else { return }
        recordAcceptance(label: label, languageId: languageId)
        var entries = intentStorage[languageId]?[intent.storageKey] ?? [:]
        entries[key] = ((entries[key]?.count ?? 0) + 1, date)
        intentStorage[languageId, default: [:]][intent.storageKey] = entries
    }
}
