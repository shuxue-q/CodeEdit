//
//  LSPService+Events.swift
//  CodeEdit
//
//  Created by Abe Malla on 6/1/24.
//

import Foundation
import JSONRPC
import LanguageClient
import LanguageServerProtocol

extension LSPService {
    func startListeningToEvents(for key: ClientKey) {
        guard let languageClient = languageClients[key] else {
            logger.error("Language client not found for \(key.languageId)")
            return
        }

        // Create a new Task to listen to the events
        let task = Task.detached { [weak self] in
            for await event in languageClient.lspInstance.eventSequence {
                await self?.handleEvent(event, for: key)
            }
        }
        eventListeningTasks[key] = task
    }

    /// Notify the document's language client that the document was saved. Only servers that run work on
    /// save hear about it (see ``LanguageServerConfiguration/didSaveLanguageIds``).
    /// - Parameter url: The url of the document that was saved.
    func documentSaved(_ url: URL) {
        guard let languageClient = languageClient(forDocument: url),
              LanguageServerConfiguration.didSaveLanguageIds.contains(languageClient.languageId) else {
            return
        }
        Task {
            do {
                try await languageClient.documentSaved(url.lspURI)
            } catch {
                self.logger.warning("Failed to send didSave for \(url.lspURI, privacy: .private): \(error)")
            }
        }
    }

    func stopListeningToEvents(for key: ClientKey) {
        if let task = eventListeningTasks[key] {
            task.cancel()
            eventListeningTasks.removeValue(forKey: key)
        }
    }

    private func handleEvent(_ event: ServerEvent, for key: ClientKey) {
        guard let client = languageClient(for: key.languageId, workspacePath: key.workspacePath) else {
            return
        }

        switch event {
        case let .request(_, request):
            handleRequest(request, client: client)
        case let .notification(notification):
            handleNotification(notification, client: client, workspacePath: key.workspacePath)
        case let .error(error):
            logger.warning("Error from server \(key.languageId, privacy: .public): \(error)")
        }
    }

    /// Answers the server requests CodeEdit has something to say to.
    ///
    /// `client/registerCapability` and `client/unregisterCapability` are answered by `InitializingServer`
    /// itself. Requests outside the LSP specification (servers' own extensions) are answered with
    /// `MethodNotFound` so the server does not wait on them. Other standard requests are left unanswered, as
    /// before; in particular an unanswered `window/workDoneProgress/create` keeps servers from streaming
    /// progress notifications CodeEdit does not show. Servers that report their indexing through progress
    /// (``LanguageServerConfiguration/workDoneProgressLanguageIds``) get a success reply; their `$/progress`
    /// notifications are dropped in ``handleNotification(_:client:workspacePath:)``.
    private func handleRequest(_ request: ServerRequest, client: LanguageServerType) {
        switch request {
        case let .workspaceConfiguration(params, handler):
            let values = LanguageServerConfiguration.workspaceConfiguration(
                for: params,
                languageId: client.languageId,
                initializationOptions: client.initializationOptions
            )
            Task { await handler(.success(values)) }
        case let .windowWorkDoneProgressCreate(_, handler):
            guard LanguageServerConfiguration.workDoneProgressLanguageIds.contains(client.languageId) else { return }
            Task { await handler(nil) }
        case let .custom(_, _, handler):
            let error = AnyJSONRPCResponseError(code: Self.methodNotFoundCode, message: "Method not found", data: nil)
            Task { await handler(.failure(error)) }
        default:
            return
        }
    }

    /// The JSON-RPC `MethodNotFound` error code. `JSONRPCErrors.methodNotFound` has the wrong sign.
    static let methodNotFoundCode = -32601

    /// Handles a server notification.
    ///
    /// Only notifications the `LanguageServerProtocol` package decodes arrive here; it drops servers' own
    /// notifications (Dart's `$/analyzerStatus` or `dart/textDocument/publishOutline`, for example) before
    /// they reach CodeEdit. CodeEdit keeps the Dart ones from being sent at all: see
    /// ``LanguageServerConfiguration/initializationOptions(for:)`` and the `workDoneProgress` window capability.
    /// rust-analyzer's `experimental/serverStatus` is only sent to clients that advertise it, which CodeEdit
    /// does not; its `$/progress` notifications (indexing, `cargo check`) fall through to `default`.
    private func handleNotification(
        _ notification: ServerNotification,
        client: LanguageServerType,
        workspacePath: String
    ) {
        switch notification {
        case let .windowLogMessage(message):
            client.logContainer.appendLog(message)
        case let .textDocumentPublishDiagnostics(params):
            // Chain completion's scratch documents do not exist on disk; their errors are not the user's.
            guard !LSPChainScratchServer.isScratchURI(params.uri) else { return }
            diagnosticsStore.update(params.diagnostics, for: params.uri, workspacePath: workspacePath)
//        case let .windowShowMessage(params):
//            print("windowShowMessage \(params.type)\n```\n\(params.message)\n```\n")
//        case let .telemetryEvent(params):
//            print("telemetryEvent: \(params)")
            //        case let .protocolCancelRequest(params):
            //            print("protocolCancelRequest: \(params)")
//        case let .protocolProgress(params):
//            print("protocolProgress: \(params)")
//        case let .protocolLogTrace(params):
//            print("protocolLogTrace: \(params)")
        default:
            return
        }
    }
}
