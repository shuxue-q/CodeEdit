//
//  TestsNavigatorViewModel.swift
//  CodeEdit
//
//  Created by CodeEdit on 22/09/2026.
//

import Foundation

/// Scans the workspace for XCTest and swift-testing declarations and publishes
/// the discovered files for the tests navigator.
@MainActor
final class TestsNavigatorViewModel: ObservableObject {
    /// Files containing test suites, sorted by file name.
    @Published private(set) var files: [DiscoveredTestFile] = []
    /// Whether a scan is currently in progress.
    @Published private(set) var isScanning = false

    /// Files larger than this (in bytes) are skipped during a scan.
    ///
    /// `nonisolated` so the off-main scan can read it. The value is a constant.
    nonisolated private static let maximumFileSize = 1_000_000

    /// Scans `workspace` for test declarations and publishes the results.
    ///
    /// File enumeration, reading, and parsing run off the main actor; only the
    /// published result is applied here.
    /// - Parameter workspace: The workspace document to scan.
    func scan(workspace: WorkspaceDocument) async {
        guard let rootURL = workspace.fileURL else {
            files = []
            return
        }
        isScanning = true
        defer { isScanning = false }
        let discovered = await Task.detached(priority: .userInitiated) {
            Self.collectTestFiles(under: rootURL)
        }.value
        guard !Task.isCancelled else { return }
        files = discovered
    }

    /// Enumerates candidate Swift files under `rootURL`, parses them, and returns
    /// the files that contain at least one test suite, sorted by file name.
    nonisolated private static func collectTestFiles(under rootURL: URL) -> [DiscoveredTestFile] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        var discovered: [DiscoveredTestFile] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift", isCandidate(fileURL) else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            if let fileSize = values?.fileSize, fileSize > maximumFileSize { continue }
            guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let suites = TestsNavigatorParser.parse(source: source)
            guard !suites.isEmpty else { continue }
            discovered.append(
                DiscoveredTestFile(
                    fileURL: fileURL,
                    fileName: fileURL.lastPathComponent,
                    suites: suites
                )
            )
        }
        return discovered.sorted {
            $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
        }
    }

    /// A file is a candidate when its name contains "test" (case-insensitive) or
    /// it lives in a directory named "Tests".
    nonisolated private static func isCandidate(_ fileURL: URL) -> Bool {
        if fileURL.lastPathComponent.localizedCaseInsensitiveContains("test") {
            return true
        }
        return fileURL.deletingLastPathComponent().pathComponents
            .contains { $0.lowercased() == "tests" }
    }
}
