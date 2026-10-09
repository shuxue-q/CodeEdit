//
//  CompletionFrequencyStore.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import Foundation

/// What the ranker knows about past acceptances for one language, intent and receiver type.
struct CompletionStatistics {
    /// `[normalizedLabel: count]` over every intent of the language: the original, coarser table.
    var languageFrequencies: [String: Int] = [:]
    /// `[normalizedLabel: count]` for the language and the intent the request is made in.
    var intentFrequencies: [String: Int] = [:]
    /// `[normalizedLabel: date]` of the last acceptance for the language and intent.
    var lastAccepted: [String: Date] = [:]
    /// `[normalizedLabel: count]` for members accepted on a receiver of the request's type. Empty when the
    /// receiver's type is unknown. Acceptances recorded with a receiver type live only here.
    var receiverFrequencies: [String: Int] = [:]
    /// `[normalizedLabel: date]` of the last acceptance on a receiver of the request's type.
    var receiverLastAccepted: [String: Date] = [:]
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
    /// What is known about `languageId`, `intent` and members of a receiver of `receiverType` (a
    /// normalized type name such as `std::vector<int>`; `nil` when unknown).
    func statistics(languageId: String, intent: CompletionIntent, receiverType: String?) -> CompletionStatistics
    /// Records that `label` was accepted on a receiver of `receiverType`. With a receiver type the
    /// acceptance counts for that type only; without one it is recorded like the intent-level variant.
    func recordAcceptance(
        label: String,
        languageId: String,
        intent: CompletionIntent,
        receiverType: String?,
        at date: Date
    )
}

extension CompletionFrequencyStoring {
    func statistics(languageId: String, intent: CompletionIntent) -> CompletionStatistics {
        CompletionStatistics(languageFrequencies: frequencies(for: languageId))
    }

    func recordAcceptance(label: String, languageId: String, intent: CompletionIntent, at date: Date) {
        recordAcceptance(label: label, languageId: languageId)
    }

    func statistics(languageId: String, intent: CompletionIntent, receiverType: String?) -> CompletionStatistics {
        statistics(languageId: languageId, intent: intent)
    }

    func recordAcceptance(
        label: String,
        languageId: String,
        intent: CompletionIntent,
        receiverType: String?,
        at date: Date
    ) {
        recordAcceptance(label: label, languageId: languageId, intent: intent, at: date)
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

    /// The per-intent file: `language → intent → label → entry`, and next to it, for members accepted on
    /// a receiver of a known type, `language → receiver type → label → entry`. Files written before
    /// receiver types existed have no `receivers`; files with it still load for older readers, which
    /// ignore the key.
    private struct StatisticsFile: Codable {
        var version = 1
        var entries: [String: [String: [String: IntentEntry]]] = [:]
        var receivers: [String: [String: [String: IntentEntry]]]?
    }

    /// The most receiver types remembered per language; the least recently used are forgotten first.
    static let maximumReceiverTypes = 200

    private var storage: [String: [String: Int]]
    private var intentStorage: [String: [String: [String: IntentEntry]]]
    private var receiverStorage: [String: [String: [String: IntentEntry]]]
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
        let loaded = Self.loadStatistics(from: self.statisticsURL)
        self.intentStorage = loaded.entries
        self.receiverStorage = loaded.receivers ?? [:]
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
        statistics(languageId: languageId, intent: intent, receiverType: nil)
    }

    func statistics(languageId: String, intent: CompletionIntent, receiverType: String?) -> CompletionStatistics {
        queue.sync {
            let entries = intentStorage[languageId]?[intent.storageKey] ?? [:]
            let receivers = receiverType.flatMap { receiverStorage[languageId]?[$0] } ?? [:]
            return CompletionStatistics(
                languageFrequencies: storage[languageId] ?? [:],
                intentFrequencies: entries.mapValues(\.count),
                lastAccepted: entries.mapValues { Date(timeIntervalSinceReferenceDate: $0.last) },
                receiverFrequencies: receivers.mapValues(\.count),
                receiverLastAccepted: receivers.mapValues { Date(timeIntervalSinceReferenceDate: $0.last) }
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

    func recordAcceptance(
        label: String,
        languageId: String,
        intent: CompletionIntent,
        receiverType: String?,
        at date: Date
    ) {
        guard let receiverType, !receiverType.isEmpty else {
            recordAcceptance(label: label, languageId: languageId, intent: intent, at: date)
            return
        }
        let key = CompletionDeduplicator.normalizedLabel(label)
        guard !key.isEmpty else { return }
        queue.sync {
            var receivers = receiverStorage[languageId] ?? [:]
            var entries = receivers[receiverType] ?? [:]
            var entry = entries[key] ?? IntentEntry(count: 0, last: 0)
            entry.count += 1
            entry.last = date.timeIntervalSinceReferenceDate
            entries[key] = entry
            receivers[receiverType] = entries
            Self.decayIfNeeded(&receivers)
            Self.forgetOldestReceivers(&receivers)
            receiverStorage[languageId] = receivers
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

    /// Scales one language's per-receiver counts down once their total is large, dropping emptied entries.
    private static func decayIfNeeded(_ receivers: inout [String: [String: IntentEntry]]) {
        let total = receivers.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } }
        guard total > decayThreshold else { return }
        for (receiver, entries) in receivers {
            var decayed = entries
            for (label, entry) in entries {
                let scaled = Int(Double(entry.count) * decayFactor)
                decayed[label] = scaled >= 1 ? IntentEntry(count: scaled, last: entry.last) : nil
            }
            receivers[receiver] = decayed.isEmpty ? nil : decayed
        }
    }

    /// Keeps the `maximumReceiverTypes` receiver types accepted from most recently.
    private static func forgetOldestReceivers(_ receivers: inout [String: [String: IntentEntry]]) {
        guard receivers.count > maximumReceiverTypes else { return }
        let lastUse = receivers.mapValues { $0.values.map(\.last).max() ?? 0 }
        let forgotten = lastUse.sorted { $0.value < $1.value }.prefix(receivers.count - maximumReceiverTypes)
        for (receiver, _) in forgotten { receivers[receiver] = nil }
    }

    private static func load(from fileURL: URL) -> [String: [String: Int]] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func loadStatistics(from fileURL: URL) -> StatisticsFile {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(StatisticsFile.self, from: data) else {
            return StatisticsFile()
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
        let (languages, intents, receivers) = queue.sync { (storage, intentStorage, receiverStorage) }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(languages) {
            try? data.write(to: fileURL, options: .atomic)
        }
        let file = StatisticsFile(entries: intents, receivers: receivers.isEmpty ? nil : receivers)
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: statisticsURL, options: .atomic)
        }
    }
}

/// An in-memory frequency store, for tests that should not touch disk.
final class InMemoryCompletionFrequencyStore: CompletionFrequencyStoring {
    private(set) var storage: [String: [String: Int]] = [:]
    private var intentStorage: [String: [String: [String: (count: Int, last: Date)]]] = [:]
    private var receiverStorage: [String: [String: [String: (count: Int, last: Date)]]] = [:]

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
        statistics(languageId: languageId, intent: intent, receiverType: nil)
    }

    func statistics(languageId: String, intent: CompletionIntent, receiverType: String?) -> CompletionStatistics {
        let entries = intentStorage[languageId]?[intent.storageKey] ?? [:]
        let receivers = receiverType.flatMap { receiverStorage[languageId]?[$0] } ?? [:]
        return CompletionStatistics(
            languageFrequencies: frequencies(for: languageId),
            intentFrequencies: entries.mapValues(\.count),
            lastAccepted: entries.mapValues(\.last),
            receiverFrequencies: receivers.mapValues(\.count),
            receiverLastAccepted: receivers.mapValues(\.last)
        )
    }

    func recordAcceptance(
        label: String,
        languageId: String,
        intent: CompletionIntent,
        receiverType: String?,
        at date: Date
    ) {
        guard let receiverType, !receiverType.isEmpty else {
            recordAcceptance(label: label, languageId: languageId, intent: intent, at: date)
            return
        }
        let key = CompletionDeduplicator.normalizedLabel(label)
        guard !key.isEmpty else { return }
        var entries = receiverStorage[languageId]?[receiverType] ?? [:]
        entries[key] = ((entries[key]?.count ?? 0) + 1, date)
        receiverStorage[languageId, default: [:]][receiverType] = entries
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
