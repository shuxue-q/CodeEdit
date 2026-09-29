//
//  MarkdownPreviewTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 28.09.26.
//

import AppKit
@testable import CodeEdit
import Foundation
import Testing

@Suite
struct MarkdownPreviewAssetResolverTests {
    @Test
    func resolvesSiblingAndIgnoresRemoteReferences() throws {
        try withTempDir { directory in
            let readme = directory.appending(path: "README.md")
            let image = directory.appending(path: "my file.png")
            try Data("pic".utf8).write(to: image)
            try Data("# Hi".utf8).write(to: readme)

            let resolved = MarkdownPreviewAssetResolver.localFile(
                reference: "my%20file.png?raw=true",
                markdownFile: readme,
                allowedRoot: directory
            )
            #expect(resolved?.standardizedFileURL == image.standardizedFileURL)
            #expect(
                MarkdownPreviewAssetResolver.localFile(
                    reference: "https://example.com/a.png",
                    markdownFile: readme,
                    allowedRoot: directory
                ) == nil
            )
            #expect(
                MarkdownPreviewAssetResolver.localFile(
                    reference: "#heading",
                    markdownFile: readme,
                    allowedRoot: directory
                ) == nil
            )
        }
    }

    @Test
    func resolvesWorkspaceRootPathAndParentInsideRoot() throws {
        try withTempDir { directory in
            let docs = directory.appending(path: "docs")
            let images = directory.appending(path: "images")
            try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
            let readme = docs.appending(path: "README.md")
            let image = images.appending(path: "a.png")
            try Data("# Hi".utf8).write(to: readme)
            try Data("pic".utf8).write(to: image)

            let fromParent = MarkdownPreviewAssetResolver.localFile(
                reference: "../images/a.png#fig",
                markdownFile: readme,
                allowedRoot: directory
            )
            let fromRoot = MarkdownPreviewAssetResolver.localFile(
                reference: "/images/a.png",
                markdownFile: readme,
                allowedRoot: directory
            )
            #expect(fromParent?.standardizedFileURL == image.standardizedFileURL)
            #expect(fromRoot?.standardizedFileURL == image.standardizedFileURL)
        }
    }

    @Test
    func rejectsPathsOutsideTheWorkspace() throws {
        try withTempDir { directory in
            let project = directory.appending(path: "proj")
            let outsideDirectory = directory.appending(path: "proj-secret")
            let docs = project.appending(path: "docs")
            try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
            let readme = docs.appending(path: "README.md")
            let secret = outsideDirectory.appending(path: "secret.png")
            let link = docs.appending(path: "link.png")
            try Data("# Hi".utf8).write(to: readme)
            try Data("no".utf8).write(to: secret)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)

            let escaped = MarkdownPreviewAssetResolver.localFile(
                reference: "../../proj-secret/secret.png",
                markdownFile: readme,
                allowedRoot: project
            )
            let linked = MarkdownPreviewAssetResolver.localFile(
                reference: "link.png",
                markdownFile: readme,
                allowedRoot: project
            )
            #expect(escaped == nil)
            #expect(linked == nil)
        }
    }
}

@MainActor
@Suite
struct MarkdownPreviewRenderTests {
    @Test
    func rendersMathCodeMermaidAlertsAndLocalImages() async throws {
        guard MarkdownPreviewResources.root != nil else {
            Issue.record("Markdown preview resources were not copied into the app bundle")
            return
        }
        try await withTempDir { directory in
            let readme = directory.appending(path: "README.md")
            let image = directory.appending(path: "dot.png")
            let png = Data(base64Encoded: Self.pixelPNG)
            try #require(png).write(to: image)
            try Self.sample.write(to: readme, atomically: true, encoding: .utf8)

            let controller = MarkdownPreviewController()
            let webView = controller.makeWebView(markdownFile: readme, allowedRoot: directory)
            let window = NSWindow(
                contentRect: NSRect(x: -4000, y: -4000, width: 1000, height: 800),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = webView
            window.orderBack(nil)
            defer { window.close() }

            let html = try await controller.renderHTML(markdown: Self.sample, isDark: false)
            #expect(html.contains("id=\"hello\""), "missing heading: \(html.prefix(400))")
            #expect(html.contains("katex"))
            #expect(!html.contains("%%MATH"))
            #expect(html.contains("keep $5 dollars$ literal"))
            #expect(html.contains("answer"))
            #expect(html.contains("markdown-alert-note"))
            #expect(html.contains("Remember this"))
            #expect(html.contains("checkbox"))
            #expect(html.contains("cemd://asset/?ref="))
            #expect(html.contains("<svg"), "mermaid did not render: \(html.suffix(400))")
        }
    }

    private static let pixelPNG = """
    iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
    """

    private static let sample = #"""
    # Hello

    Inline $E = mc^2$.

    $$
    \int_0^1 x^2 \, dx
    $$

    ```text
    keep $5 dollars$ literal
    ```

    ```swift
    let answer = 42
    ```

    ```mermaid
    flowchart LR
      A-->B
    ```

    > [!NOTE]
    > Remember this

    - [x] Done

    ![dot](dot.png)
    """#
}
