//
//  CEWorkspaceSettingsManager.swift
//  CodeEdit
//
//  Created by Axel Martinez on 27/3/24.
//

import SwiftUI
import Combine

/// The CodeEdit workspace settings model.
final class CEWorkspaceSettings: ObservableObject {
    @Published public var settings: CEWorkspaceSettingsData = .init()

    private var storeTask: AnyCancellable?
    private let fileManager = FileManager.default

    private(set) var folderURL: URL

    var settingsURL: URL {
        folderURL.appending(path: "settings").appendingPathExtension("json")
    }

    init(workspaceURL: URL) {
        folderURL = workspaceURL.appending(path: ".codeedit", directoryHint: .isDirectory)
        loadSettings()

        storeTask = $settings
            .receive(on: DispatchQueue.main)
            .throttle(for: 2.0, scheduler: RunLoop.main, latest: true)
            .sink { _ in
                try? self.savePreferences()
            }
    }

    func cleanUp() {
        storeTask?.cancel()
        storeTask = nil
    }

    deinit {
        cleanUp()
    }

    /// Load and construct ``CEWorkspaceSettings`` model from `.codeedit/settings.json`
    private func loadSettings() {
        guard fileManager.fileExists(atPath: settingsURL.path),
              let json = try? Data(contentsOf: settingsURL),
              let prefs = try? JSONDecoder().decode(CEWorkspaceSettingsData.self, from: json)
        else { return }
        self.settings = prefs
    }

    /// Re-reads `.codeedit/settings.json` after it was edited as text, updating the existing
    /// ``settings`` object in place because ``TaskManager`` keeps a reference to it.
    /// - Returns: `false` when the file exists but cannot be decoded; the current values are kept.
    @discardableResult
    func reloadFromDisk() -> Bool {
        let loaded: CEWorkspaceSettingsData
        if fileManager.fileExists(atPath: settingsURL.path) {
            guard let json = try? Data(contentsOf: settingsURL),
                  let prefs = try? JSONDecoder().decode(CEWorkspaceSettingsData.self, from: json)
            else { return false }
            loaded = prefs
        } else {
            loaded = CEWorkspaceSettingsData()
        }
        settings.project = loaded.project
        settings.tasks = loaded.tasks
        settings.navigator = loaded.navigator
        return true
    }

    /// Changes the navigator settings and saves them.
    func updateNavigator(_ update: (inout NavigatorSettings) -> Void) {
        var navigator = settings.navigator
        update(&navigator)
        guard navigator != settings.navigator else { return }
        settings.navigator = navigator
        try? savePreferences()
    }

    /// Save``CEWorkspaceSettingsManager`` model to `.codeedit/settings.json`
    func savePreferences() throws {
        // If the user doesn't have any settings to save, don't save them.
        guard !settings.isEmpty() else {
            // Settings is empty, remove the file & directory if it's empty.
            if fileManager.fileExists(atPath: settingsURL.path()) {
                try fileManager.removeItem(at: settingsURL)

                if try fileManager.contentsOfDirectory(atPath: folderURL.path()).isEmpty {
                    try fileManager.removeItem(at: folderURL)
                }
            }
            return
        }

        if !fileManager.fileExists(atPath: folderURL.path()) {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }

        let data = try JSONEncoder().encode(settings)
        let json = try JSONSerialization.jsonObject(with: data)
        let prettyJSON = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try prettyJSON.write(to: settingsURL, options: .atomic)
    }
}
