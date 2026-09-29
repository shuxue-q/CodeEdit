//
//  BreakpointStore.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/21/26.
//

import Foundation
import Combine

/// Application-wide store of source breakpoints, persisted to `UserDefaults`.
///
/// Breakpoints are tracked per absolute file path as a set of 0-based line
/// indexes (the editor's line numbering). Conversion to DAP's 1-based lines
/// happens in ``DebugService`` when syncing with the adapter.
@MainActor
final class BreakpointStore: ObservableObject {
    /// The shared breakpoint store.
    static let shared = BreakpointStore()

    /// File path → set of 0-based line indexes with breakpoints.
    @Published private(set) var breakpoints: [String: Set<Int>] {
        didSet { persist() }
    }

    /// Global breakpoint enable switch, kept independent of any session state.
    /// The breakpoints navigator reflects it, and ``DebugService`` honors it by
    /// sending an empty breakpoint set to the adapter while it is disabled.
    @Published var isEnabled: Bool {
        didSet { persist() }
    }

    private static let defaultsKey = "CodeEdit.DebugBreakpoints"

    /// Codable payload persisted under ``defaultsKey``.
    private struct PersistedState: Codable {
        let breakpoints: [String: Set<Int>]
        let isEnabled: Bool
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let state = try? JSONDecoder().decode(PersistedState.self, from: data) {
            breakpoints = state.breakpoints
            isEnabled = state.isEnabled
        } else {
            breakpoints = [:]
            isEnabled = true
        }
    }

    /// Toggles a breakpoint at the given 0-based line in the file at `filePath`.
    func toggle(filePath: String, line: Int) {
        var lines = breakpoints[filePath] ?? []
        if lines.contains(line) {
            lines.remove(line)
        } else {
            lines.insert(line)
        }
        if lines.isEmpty {
            breakpoints.removeValue(forKey: filePath)
        } else {
            breakpoints[filePath] = lines
        }
    }

    /// Returns the 0-based breakpoint lines for the file at `filePath`.
    func lines(for filePath: String) -> Set<Int> {
        breakpoints[filePath] ?? []
    }

    /// Removes all breakpoints in all files.
    func clearAll() {
        breakpoints = [:]
    }

    private func persist() {
        let state = PersistedState(breakpoints: breakpoints, isEnabled: isEnabled)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
