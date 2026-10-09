//
//  CompletionMetricsStore.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// Receives measurements of how completion behaves, so latency and ranking quality can be checked
/// against real use. Everything stays on this computer.
@MainActor
protocol CompletionMetricsRecording: AnyObject {
    /// A completion window opened.
    func recordPopup()
    /// A provider took `duration` to answer a request, including answers that arrived too late to show.
    func recordProviderLatency(source: CompletionSource, duration: Duration)
    /// An item was accepted.
    /// - Parameters:
    ///   - rank: The item's row in the list at that moment, `0` being the first.
    ///   - keystrokes: How many times the list was refreshed between the window opening and the
    ///     acceptance, which is one per typed character.
    func recordAcceptance(rank: Int, keystrokes: Int)
}

/// Collects completion metrics for the current app session and keeps a short history in
/// `~/Library/Application Support/CodeEdit/completion-metrics.json`. Local only: nothing is sent anywhere.
///
/// Per session it records the number of popups and acceptances, the average rank of accepted items,
/// the average keystrokes between a popup and an acceptance, and each provider's p50 and p95 latency.
@MainActor
final class CompletionMetricsStore: CompletionMetricsRecording {
    /// The app-wide store.
    static let shared = CompletionMetricsStore()

    /// Sessions kept in the file, the current one included.
    static let maximumSessions = 30
    /// Latency samples kept per provider and session; the oldest are dropped first.
    static let maximumLatencySamples = 1_000
    /// How long to wait after a change before writing to disk.
    static let saveDelay: TimeInterval = 5

    /// A provider's response times.
    struct LatencySummary: Codable, Equatable {
        /// How many answers were measured.
        var count: Int
        /// The median response time, in milliseconds.
        var p50Milliseconds: Double
        /// The 95th-percentile response time, in milliseconds.
        var p95Milliseconds: Double
    }

    /// The metrics of one app session.
    struct SessionSummary: Codable, Equatable {
        /// When the session started.
        var startedAt: Date
        /// Completion windows opened.
        var popupCount: Int
        /// Items accepted.
        var acceptCount: Int
        /// The mean row of accepted items (`0` is the first row), if any were accepted.
        var averageAcceptedRank: Double?
        /// The mean number of list refreshes between a popup and an acceptance, if any were accepted.
        var averageKeystrokesToAccept: Double?
        /// Response times by provider source (`lsp`, `word`, …).
        var providerLatencies: [String: LatencySummary]
    }

    private struct HistoryFile: Codable {
        var version = 1
        var sessions: [SessionSummary] = []
    }

    private let fileURL: URL
    private let startedAt: Date
    private var history: [SessionSummary]
    private var popupCount = 0
    private var acceptedRanks: [Int] = []
    private var acceptedKeystrokes: [Int] = []
    private var latencies: [String: [Double]] = [:]
    private var saveWorkItem: DispatchWorkItem?

    /// Creates a store that writes to `fileURL`, by default under Application Support.
    init(fileURL: URL? = nil, now: Date = Date()) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.startedAt = now
        self.history = Self.load(from: self.fileURL)
    }

    /// `~/Library/Application Support/CodeEdit/completion-metrics.json`.
    static var defaultFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("CodeEdit", isDirectory: true)
            .appendingPathComponent("completion-metrics.json")
    }

    // MARK: - Recording

    func recordPopup() {
        popupCount += 1
        scheduleSave()
    }

    func recordProviderLatency(source: CompletionSource, duration: Duration) {
        let components = duration.components
        let milliseconds = Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
        var samples = latencies[source.rawValue, default: []]
        samples.append(milliseconds)
        if samples.count > Self.maximumLatencySamples {
            samples.removeFirst(samples.count - Self.maximumLatencySamples)
        }
        latencies[source.rawValue] = samples
        scheduleSave()
    }

    func recordAcceptance(rank: Int, keystrokes: Int) {
        acceptedRanks.append(rank)
        acceptedKeystrokes.append(keystrokes)
        scheduleSave()
    }

    // MARK: - Reading

    /// The metrics gathered since this store was created.
    func currentSession() -> SessionSummary {
        SessionSummary(
            startedAt: startedAt,
            popupCount: popupCount,
            acceptCount: acceptedRanks.count,
            averageAcceptedRank: Self.mean(acceptedRanks),
            averageKeystrokesToAccept: Self.mean(acceptedKeystrokes),
            providerLatencies: latencies.mapValues { samples in
                LatencySummary(
                    count: samples.count,
                    p50Milliseconds: Self.percentile(samples, 0.5),
                    p95Milliseconds: Self.percentile(samples, 0.95)
                )
            }
        )
    }

    /// Past sessions from the file, oldest first, without the current one.
    var previousSessions: [SessionSummary] {
        history.filter { $0.startedAt != startedAt }
    }

    /// The `fraction` percentile of `samples` by the nearest-rank method; `0` for no samples.
    static func percentile(_ samples: [Double], _ fraction: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let rank = Int((fraction * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }

    private static func mean(_ values: [Int]) -> Double? {
        values.isEmpty ? nil : Double(values.reduce(0, +)) / Double(values.count)
    }

    // MARK: - Persistence

    private static func load(from fileURL: URL) -> [SessionSummary] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(HistoryFile.self, from: data))?.sessions ?? []
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.save() }
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: workItem)
    }

    /// Writes the history, with the current session replacing its earlier snapshot, right away.
    func save() {
        var sessions = previousSessions
        sessions.append(currentSession())
        sessions = Array(sessions.suffix(Self.maximumSessions))
        history = sessions

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(HistoryFile(sessions: sessions)) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
