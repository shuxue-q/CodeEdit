//
//  MarkdownPreviewController.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 28.09.26.
//

import AppKit
import Combine
import WebKit

enum MarkdownPreviewError: Error, Equatable {
    case missingResources
    case pageFailed(String)
}

/// Loads the offline preview page and pushes Markdown into it.
@MainActor
final class MarkdownPreviewController: NSObject, WKNavigationDelegate {
    private(set) var webView: WKWebView?
    private var handler: MarkdownPreviewSchemeHandler?
    private var contentCancellable: AnyCancellable?
    private weak var subscribedDocument: CodeFileDocument?
    private var onOpenFile: (URL) -> Void = { _ in }
    private var pageReady = false
    private var submittedMarkdown: String?
    private var submittedScheme = "light"
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var renderContinuation: CheckedContinuation<String, Error>?

    func makeWebView(markdownFile: URL, allowedRoot: URL) -> WKWebView {
        if let webView { return webView }
        guard let bundleRoot = MarkdownPreviewResources.root, let indexURL = MarkdownPreviewResources.indexURL else {
            return WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        }
        let handler = MarkdownPreviewSchemeHandler(
            bundleRoot: bundleRoot,
            markdownFile: markdownFile,
            allowedRoot: allowedRoot
        )
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: MarkdownPreviewScheme.name)
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 980, height: 800), configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = false
        self.handler = handler
        self.webView = webView
        webView.load(URLRequest(url: indexURL))
        return webView
    }

    func update(
        document: CodeFileDocument,
        markdownFile: URL,
        allowedRoot: URL,
        isDark: Bool,
        onOpenFile: @escaping (URL) -> Void
    ) {
        handler?.update(markdownFile: markdownFile, allowedRoot: allowedRoot)
        self.onOpenFile = onOpenFile
        subscribe(to: document)
        render(markdown: document.content?.string ?? "", isDark: isDark)
    }

    func renderHTML(markdown: String, isDark: Bool) async throws -> String {
        try await waitUntilReady()
        return try await withCheckedThrowingContinuation { continuation in
            renderContinuation = continuation
            render(markdown: markdown, isDark: isDark, force: true)
        }
    }

    func invalidate() {
        contentCancellable?.cancel()
        contentCancellable = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        failWaiting(MarkdownPreviewError.pageFailed("Preview closed."))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
        readyContinuation?.resume()
        readyContinuation = nil
        pushRender()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failWaiting(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        failWaiting(error)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if url.scheme == MarkdownPreviewScheme.name, url.host == MarkdownPreviewScheme.bundleHost {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        // `target=_blank` has no target frame. `createWebViewWith` opens that URL.
        if navigationAction.targetFrame != nil {
            open(url)
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            open(url)
        }
        return nil
    }

    private func subscribe(to document: CodeFileDocument) {
        guard subscribedDocument !== document else { return }
        subscribedDocument = document
        contentCancellable = document.contentCoordinator.textUpdatePublisher
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self, weak document] _ in
                guard let self, let document else { return }
                self.render(markdown: document.content?.string ?? "", isDark: self.submittedScheme == "dark")
            }
    }

    private func render(markdown: String, isDark: Bool, force: Bool = false) {
        let scheme = isDark ? "dark" : "light"
        if !force, submittedMarkdown == markdown, submittedScheme == scheme { return }
        submittedMarkdown = markdown
        submittedScheme = scheme
        applyAppearance(isDark: isDark)
        guard pageReady else { return }
        pushRender()
    }

    private func applyAppearance(isDark: Bool) {
        let appearance: NSAppearance.Name = isDark ? .darkAqua : .aqua
        webView?.appearance = NSAppearance(named: appearance)
        webView?.underPageBackgroundColor = isDark
            ? NSColor(srgbRed: 13 / 255, green: 17 / 255, blue: 23 / 255, alpha: 1)
            : .white
    }

    private func pushRender() {
        guard pageReady, let markdown = submittedMarkdown, let webView else { return }
        let scheme = submittedScheme
        let arguments = ["markdown": markdown, "scheme": scheme]
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let value = try await webView.callAsyncJavaScript(
                    "return window.renderMarkdown(markdown, scheme)",
                    arguments: arguments,
                    in: nil,
                    contentWorld: .page
                )
                self.finishRender(.success(value as? String ?? ""))
            } catch {
                self.finishRender(.failure(error))
            }
        }
    }

    private func finishRender(_ result: Result<String, Error>) {
        switch result {
        case .success(let html):
            renderContinuation?.resume(returning: html)
        case .failure(let error):
            renderContinuation?.resume(throwing: error)
        }
        renderContinuation = nil
    }

    private func waitUntilReady() async throws {
        if pageReady { return }
        if MarkdownPreviewResources.root == nil || webView == nil {
            throw MarkdownPreviewError.missingResources
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            if pageReady {
                continuation.resume()
            } else {
                readyContinuation = continuation
            }
        }
    }

    private func failWaiting(_ error: Error) {
        readyContinuation?.resume(throwing: error)
        readyContinuation = nil
        renderContinuation?.resume(throwing: error)
        renderContinuation = nil
    }

    private func open(_ url: URL) {
        if url.scheme == MarkdownPreviewScheme.name, url.host == MarkdownPreviewScheme.assetHost {
            openAsset(url)
            return
        }
        guard let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openAsset(_ url: URL) {
        guard let handler, let reference = MarkdownPreviewScheme.reference(from: url) else { return }
        let paths = handler.paths()
        guard let file = MarkdownPreviewAssetResolver.localFile(
            reference: reference,
            markdownFile: paths.markdownFile,
            allowedRoot: paths.allowedRoot
        ) else {
            return
        }
        onOpenFile(file)
    }
}
