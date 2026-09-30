//
//  CEWorkspaceSettingsTests.swift
//  CodeEditTests
//
//  Created by Khan Winter on 4/21/25.
//

import Foundation
import Testing
@testable import CodeEdit

struct CEWorkspaceSettingsTests {
    let settings: CEWorkspaceSettings = CEWorkspaceSettings(workspaceURL: URL(filePath: "/"))

    @Test
    func settingsURLNoSpace() async throws {
        #expect(settings.folderURL.lastPathComponent == ".codeedit")
        #expect(settings.settingsURL.lastPathComponent == "settings.json")
    }

    @Test
    func navigatorSettingsRoundTripAndDefaults() throws {
        let empty = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data("{}".utf8))
        #expect(empty.navigator == NavigatorSettings())
        #expect(empty.isEmpty())

        let data = CEWorkspaceSettingsData()
        data.navigator.showHiddenFiles = true
        data.navigator.excludedPatterns = ["build/"]
        let decoded = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: JSONEncoder().encode(data))
        #expect(decoded.navigator == data.navigator)
    }

    @Test
    func reloadFromDiskUpdatesSettingsInPlace() throws {
        try withTempDir { dir in
            let manager = CEWorkspaceSettings(workspaceURL: dir)
            let original = manager.settings
            manager.updateNavigator { $0.showHiddenFiles = true }
            #expect(FileManager.default.fileExists(atPath: manager.settingsURL.path))

            let json = #"{"navigator":{"excludedPatterns":["*.o"]},"tasks":[]}"#
            try json.write(to: manager.settingsURL, atomically: true, encoding: .utf8)
            #expect(manager.reloadFromDisk())
            #expect(manager.settings === original)
            #expect(manager.settings.navigator.showHiddenFiles == false)
            #expect(manager.settings.navigator.excludedPatterns == ["*.o"])

            try "not json".write(to: manager.settingsURL, atomically: true, encoding: .utf8)
            #expect(!manager.reloadFromDisk())
            #expect(manager.settings.navigator.excludedPatterns == ["*.o"])
            manager.cleanUp()
        }
    }
}
