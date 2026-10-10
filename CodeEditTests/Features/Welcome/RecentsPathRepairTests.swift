//
//  RecentsPathRepairTests.swift
//  CodeEditTests
//
//  Created by CodeEdit on 10/10/26.
//

import Testing
import Foundation
import WelcomeWindow
@testable import CodeEdit

@Suite(.serialized)
@MainActor
struct RecentsPathRepairTests {
    private let defaults: UserDefaults
    private let root: URL

    init() throws {
        let name = "RecentsPathRepairTests.\(UUID())"
        defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "RecentsPathRepairTests_\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        // Use the canonical path (`/private/var/…`, as bookmarks resolve) so the only path difference
        // is the one under test.
        let canonical = try #require(temp.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath)
        root = URL(filePath: canonical, directoryHint: .isDirectory)
    }

    /// Points `RecentsStore` at this test's defaults. Called at the top of each (synchronous) test body:
    /// other suites swap the shared `RecentsStore.defaults` between suite init and test body.
    private func useTestDefaults() {
        RecentsStore.defaults = defaults
    }

    private func makeFile(_ name: String) -> URL {
        let url = root.appending(path: name)
        FileManager.default.createFile(atPath: url.path, contents: Data())
        return url
    }

    @Test
    func doubleSlashEntryBecomesRemovable() throws {
        useTestDefaults()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = makeFile("main.cpp")
        let other = makeFile("other.txt")
        RecentsStore.documentOpened(at: other)
        // What `codeedit://file//Users/…` used to record.
        RecentsStore.documentOpened(at: URL(fileURLWithPath: "/" + file.path))

        let listed = try #require(RecentsStore.recentProjectURLs().first)
        #expect(listed.path == file.path)
        // The welcome window removes by the listed (resolved) URL, which misses the `//` entry.
        #expect(RecentsStore.removeRecentProjects([listed]).count == 2)

        #expect(RecentsPathRepair.repair(defaults: defaults))
        #expect(RecentsStore.recentProjectURLs().map(\.path) == [file.path, other.path])

        let remaining = RecentsStore.removeRecentProjects([listed])
        #expect(remaining.map(\.path) == [other.path])
    }

    @Test
    func duplicatesCollapseAndCleanListIsUntouched() throws {
        useTestDefaults()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = makeFile("CMakeLists.txt")
        RecentsStore.documentOpened(at: file)
        RecentsStore.documentOpened(at: URL(fileURLWithPath: "/" + file.path))

        #expect(RecentsPathRepair.repair(defaults: defaults))
        #expect(!RecentsPathRepair.repair(defaults: defaults))
        #expect(RecentsStore.removeRecentProjects([file]).isEmpty)
    }
}
