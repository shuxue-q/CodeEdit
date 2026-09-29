//
//  LSPContentCoordinator.swift
//  CodeEdit
//
//  Created by Khan Winter on 9/12/24.
//

import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import LanguageServerProtocol

/// This content coordinator forwards content notifications from the editor's text storage to a language service.
///
/// This is a text view coordinator so that it can be installed on an open editor. It is kept as a property on
/// ``CodeFileDocument`` since the language server does all it's document management using instances of that type.
///
/// Language servers expect edits to be sent in chunks (and it helps reduce processing overhead). To do this, this class
/// batches edits for 250ms before sending them to the ``LanguageServer``. Interactive requests can flush that batch
/// immediately so the server sees the same document as the editor.
class LSPContentCoordinator<DocumentType: LanguageServerDocument>: TextViewCoordinator, TextViewDelegate {
    // Required to avoid a large_tuple lint error
    private struct SequenceElement: Sendable {
        let uri: String
        let range: LSPRange
        let string: String
    }

    private var editedRange: LSPRange?
    private var pendingChanges: [SequenceElement] = []
    private var task: Task<Void, Never>?
    private var sendingTask: Task<Void, Error>?
    /// Identifies the in-flight send so a newer batch is not cleared when an older one fails.
    private var sendGeneration = 0
    /// The in-flight semantic token refresh. Not awaited by ``flushPendingChanges()``.
    private var highlightTask: Task<Void, Never>?
    /// Set when edits are sent during a refresh, so one more refresh runs after it.
    private var needsHighlightRefresh = false

    weak var languageServer: LanguageServer<DocumentType>?
    var documentURI: String?

    /// Initializes a content coordinator.
    init(documentURI: String? = nil, languageServer: LanguageServer<DocumentType>? = nil) {
        self.documentURI = documentURI
        self.languageServer = languageServer
    }

    @MainActor
    func setUp(server: LanguageServer<DocumentType>, document: DocumentType) {
        languageServer = server
        documentURI = document.languageServerURI
    }

    func setUpUpdatesTask() {
        task?.cancel()
        task = nil
        guard !pendingChanges.isEmpty else { return }
        task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                try await self?.flushPendingChanges()
            } catch {
                // Cancellation is expected; documentChanged logs transport errors.
            }
        }
    }

    /// Sends queued edits and waits for earlier batches before an interactive LSP request.
    @MainActor
    func flushPendingChanges() async throws {
        task?.cancel()
        task = nil
        if let languageServer, let uri = pendingChanges.first?.uri {
            let changes = pendingChanges.map {
                LanguageServer<DocumentType>.DocumentChange(replacingContentsIn: $0.range, with: $0.string)
            }
            pendingChanges.removeAll()
            let previousTask = sendingTask
            sendGeneration += 1
            sendingTask = Task { @MainActor [weak self] in
                // Keep incremental edits ordered even when another flush arrives during a send.
                _ = try? await previousTask?.value
                try Task.checkCancellation()
                try await languageServer.documentChanged(uri: uri, changes: changes)
                self?.scheduleHighlightRefresh(uri: uri)
            }
        }
        guard let currentTask = sendingTask else { return }
        let awaitedGeneration = sendGeneration
        do {
            try await currentTask.value
        } catch {
            // A failed batch must not stay in `sendingTask`. Later flushes with nothing new would
            // otherwise rethrow it, and completion would stay closed.
            if sendGeneration == awaitedGeneration {
                sendingTask = nil
            }
            throw error
        }
    }

    /// Requests semantic tokens after edits were sent, without holding up completion.
    ///
    /// Only one token request runs at a time so deltas apply in order. Edits sent while it runs are
    /// covered by a single follow-up request.
    @MainActor
    private func scheduleHighlightRefresh(uri: String) {
        guard highlightTask == nil else {
            needsHighlightRefresh = true
            return
        }
        highlightTask = Task { @MainActor [weak self] in
            while let self, let languageServer = self.languageServer, !Task.isCancelled {
                self.needsHighlightRefresh = false
                await languageServer.refreshHighlighting(uri: uri)
                guard self.needsHighlightRefresh else { break }
            }
            self?.highlightTask = nil
        }
    }

    func prepareCoordinator(controller: TextViewController) {
        setUpUpdatesTask()
    }

    /// We grab the lsp range before the content (and layout) is changed so we get correct line/col info for the
    /// language server range.
    func textView(_ textView: TextView, willReplaceContentsIn range: NSRange, with string: String) {
        self.editedRange = textView.lspRangeFrom(nsRange: range)
    }

    func textView(_ textView: TextView, didReplaceContentsIn range: NSRange, with string: String) {
        guard let lspRange = editedRange, let documentURI else {
            return
        }
        self.editedRange = nil
        pendingChanges.append(SequenceElement(uri: documentURI, range: lspRange, string: string))
        if task == nil {
            setUpUpdatesTask()
        }
    }

    func destroy() {
        task?.cancel()
        task = nil
        sendingTask?.cancel()
        sendingTask = nil
        highlightTask?.cancel()
        highlightTask = nil
        needsHighlightRefresh = false
        pendingChanges.removeAll()
    }

    deinit {
        destroy()
    }
}
