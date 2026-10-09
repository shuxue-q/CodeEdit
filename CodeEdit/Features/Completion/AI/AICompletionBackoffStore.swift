//
//  AICompletionBackoffStore.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

/// Remembers that the AI server refused the current configuration, so no provider sends another request
/// until the pause is over, the configuration changes, or a connection test succeeds.
///
/// The app shares one store, ``shared``, between every document's provider and the settings page, so a wrong
/// key or model name pauses all of them, and Test Connection can end the pause. Safe to use from any thread.
final class AICompletionBackoffStore: @unchecked Sendable {
    /// The store the app's providers and the settings page use.
    static let shared = AICompletionBackoffStore()

    private struct Entry {
        let until: ContinuousClock.Instant
        let kind: AIBackendKind
        let configuration: AIBackendConfiguration
    }

    private let lock = NSLock()
    private var entry: Entry?

    /// Creates an empty store.
    init() { }

    /// Pauses requests for `kind` and `configuration` until `until`.
    func start(until: ContinuousClock.Instant, kind: AIBackendKind, configuration: AIBackendConfiguration) {
        lock.withLock { entry = Entry(until: until, kind: kind, configuration: configuration) }
    }

    /// Whether requests for `kind` and `configuration` are paused at `now`. A pause recorded for another
    /// provider, model, base URL or key is dropped: changing any of them ends the pause.
    func isBackedOff(kind: AIBackendKind, configuration: AIBackendConfiguration, now: ContinuousClock.Instant) -> Bool {
        lock.withLock {
            guard let entry else { return false }
            guard entry.kind == kind, entry.configuration == configuration else {
                self.entry = nil
                return false
            }
            return now < entry.until
        }
    }

    /// Ends the pause recorded for `kind` and `configuration`, if there is one.
    func clear(kind: AIBackendKind, configuration: AIBackendConfiguration) {
        lock.withLock {
            if entry?.kind == kind, entry?.configuration == configuration { entry = nil }
        }
    }
}
