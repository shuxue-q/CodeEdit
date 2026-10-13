//
//  HybridProjectPaneCaptureTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 10/13/26.
//

import AppKit
import SwiftUI
import Testing
@testable import CodeEdit

/// Renders the hybrid project panes over ``HybridProjectFixture`` in a real window and saves what
/// the window shows as PNG files, for checking the layout by eye.
///
/// Runs only when `PANE_CAPTURE_DIR` is set (pass `TEST_RUNNER_PANE_CAPTURE_DIR` to `xcodebuild`).
@MainActor
@Suite(.serialized)
struct HybridProjectPaneCaptureTests {
    nonisolated private static var captureDirectory: URL? {
        ProcessInfo.processInfo.environment["PANE_CAPTURE_DIR"].map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    @Test(.enabled(if: captureDirectory != nil))
    func capturesThePanes() async throws {
        let output = try #require(Self.captureDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try await withTempDir { root in
            try HybridProjectFixture.write(in: root)
            let inventory = ProjectInventoryModel(workspaceDirectory: root)
            inventory.reload()
            await inventory.waitForReload()
            let flutter = FlutterWorkspace(workspaceDirectory: root)
            flutter.reload()
            await flutter.waitForReload()
            let state = ProjectEditorState(rootURL: root, includesCMakeSettings: true, includesFlutterSettings: true)
            state.updateDiscoveredFiles(
                inventory.inventory?.configurationFiles ?? [],
                toolchains: inventory.inventory?.toolchains ?? []
            )
            // Let the SDK lookup and toolchain probes finish so the panes show real versions.
            try await Task.sleep(for: .seconds(6))

            try await capture(
                ProjectOverviewPane(model: inventory, flutterWorkspace: flutter, select: { _ in }),
                name: "overview",
                to: output
            )
            try await capture(
                FlutterProjectPane(flutterWorkspace: flutter, inventory: inventory.inventory, runTask: { _, _ in }),
                name: "flutter",
                to: output
            )
            try await capture(
                RustProjectPane(model: inventory, state: state, runTask: { _, _ in }),
                name: "rust",
                to: output
            )
            try await capture(
                ProjectFilesPane(state: state, workspaceSettings: nil, openInTab: { _ in }),
                name: "project-files",
                to: output
            )
        }
    }

    private func capture(_ view: some View, name: String, to directory: URL) async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: 860, height: 1_000),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .floating
        let hostingView = NSHostingView(rootView: view.frame(width: 860, height: 1_000))
        window.contentView = hostingView
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .seconds(2))
        window.display()
        try await Task.sleep(for: .milliseconds(500))
        if let image = Self.windowImage(window) {
            try write(NSBitmapImageRep(cgImage: image), to: directory.appending(path: "\(name).png"))
        }
        // The view's own rendering, in case the window server capture is blank in the test host.
        if let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) {
            hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
            try write(bitmap, to: directory.appending(path: "\(name)-view.png"))
        }
    }

    private func write(_ bitmap: NSBitmapImageRep, to url: URL) throws {
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: url)
    }

    /// Captures the window's composited pixels. `CGWindowListCreateImage` is marked unavailable
    /// in the SDK but still works for the process's own windows without Screen Recording access.
    private static func windowImage(_ window: NSWindow) -> CGImage? {
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else { return nil }
        let capture = unsafeBitCast(symbol, to: Capture.self)
        let includingWindow: UInt32 = 1 << 3
        let imageOptions: UInt32 = (1 << 0) | (1 << 4)
        return capture(.null, includingWindow, UInt32(window.windowNumber), imageOptions)?.takeRetainedValue()
    }
}
