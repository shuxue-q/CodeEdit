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
            sendingTask = Task { @MainActor in
                // Keep incremental edits ordered even when another flush arrives during a send.
                _ = try? await previousTask?.value
                try Task.checkCancellation()
                try await languageServer.documentChanged(uri: uri, changes: changes)
            }
        }
        try await sendingTask?.value
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
        pendingChanges.removeAll()
    }

    deinit {
        destroy()
    }
}
