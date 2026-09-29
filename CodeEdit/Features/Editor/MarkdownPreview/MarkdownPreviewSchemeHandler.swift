//
//  MarkdownPreviewSchemeHandler.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 28.09.26.
//

import Foundation
import WebKit

/// Serves the preview page and workspace images through the `cemd` scheme.
///
/// The page lives in the app bundle. Images and relative links live next to the Markdown file.
/// One custom scheme can read both without granting the web view broad file access.
final class MarkdownPreviewSchemeHandler: NSObject, WKURLSchemeHandler {
    let bundleRoot: URL
    private let lock = NSLock()
    private var markdownFile: URL
    private var allowedRoot: URL
    private var stoppedTasks: Set<ObjectIdentifier> = []

    init(bundleRoot: URL, markdownFile: URL, allowedRoot: URL) {
        self.bundleRoot = bundleRoot
        self.markdownFile = markdownFile
        self.allowedRoot = allowedRoot
    }

    func update(markdownFile: URL, allowedRoot: URL) {
        lock.lock()
        self.markdownFile = markdownFile
        self.allowedRoot = allowedRoot
        lock.unlock()
    }

    func paths() -> (markdownFile: URL, allowedRoot: URL) {
        lock.lock()
        defer { lock.unlock() }
        return (markdownFile, allowedRoot)
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            fail(urlSchemeTask, status: 400)
            return
        }
        switch url.host {
        case MarkdownPreviewScheme.bundleHost:
            serveBundleFile(url, task: urlSchemeTask)
        case MarkdownPreviewScheme.assetHost:
            serveAsset(url, task: urlSchemeTask)
        default:
            fail(urlSchemeTask, status: 404)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        lock.lock()
        stoppedTasks.insert(ObjectIdentifier(urlSchemeTask))
        lock.unlock()
    }

    private func serveBundleFile(_ url: URL, task: WKURLSchemeTask) {
        guard let file = fileInside(root: bundleRoot, requestPath: url.path) else {
            fail(task, status: 404)
            return
        }
        serve(file, url: url, task: task)
    }

    private func serveAsset(_ url: URL, task: WKURLSchemeTask) {
        guard let reference = MarkdownPreviewScheme.reference(from: url) else {
            fail(task, status: 400)
            return
        }
        let paths = paths()
        guard let file = MarkdownPreviewAssetResolver.localFile(
            reference: reference,
            markdownFile: paths.markdownFile,
            allowedRoot: paths.allowedRoot
        ) else {
            fail(task, status: 404)
            return
        }
        serve(file, url: url, task: task)
    }

    private func serve(_ file: URL, url: URL, task: WKURLSchemeTask) {
        guard let data = try? Data(contentsOf: file), data.count <= 32 * 1024 * 1024 else {
            fail(task, status: 404)
            return
        }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": Self.mimeType(for: file),
                "Content-Length": String(data.count),
                "Cache-Control": "no-cache",
                "Access-Control-Allow-Origin": "*"
            ]
        ) else {
            fail(task, status: 500)
            return
        }
        complete(task, response: response, data: data)
    }

    private func fileInside(root: URL, requestPath: String) -> URL? {
        let decoded = requestPath.removingPercentEncoding ?? requestPath
        let relative = decoded.hasPrefix("/") ? String(decoded.dropFirst()) : decoded
        let parts = relative.split(separator: "/").map(String.init)
        guard !relative.isEmpty, !parts.contains(".."), !parts.contains(".") else { return nil }
        let file = root.appending(path: relative).standardizedFileURL
        let rootURL = root.standardizedFileURL
        let fileParts = file.pathComponents
        let rootParts = rootURL.pathComponents
        guard fileParts.count >= rootParts.count,
              Array(fileParts.prefix(rootParts.count)) == rootParts else {
            return nil
        }
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return file
    }

    private func fail(_ task: WKURLSchemeTask, status: Int) {
        guard let url = task.request.url else { return }
        let body = Data("Not found".utf8)
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "text/plain; charset=utf-8",
                "Content-Length": String(body.count),
                "Cache-Control": "no-store"
            ]
        ) else {
            return
        }
        complete(task, response: response, data: body)
    }

    private func complete(_ task: WKURLSchemeTask, response: URLResponse, data: Data) {
        guard !isStopped(task) else { return }
        task.didReceive(response)
        guard !isStopped(task) else { return }
        task.didReceive(data)
        guard !isStopped(task) else { return }
        task.didFinish()
    }

    private func isStopped(_ task: WKURLSchemeTask) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stoppedTasks.contains(ObjectIdentifier(task))
    }

    private static func mimeType(for file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "html", "htm":
            return "text/html; charset=utf-8"
        case "js":
            return "text/javascript; charset=utf-8"
        case "css":
            return "text/css; charset=utf-8"
        case "woff2":
            return "font/woff2"
        case "svg":
            return "image/svg+xml"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        default:
            return "application/octet-stream"
        }
    }
}
