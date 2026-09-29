//
//  LSPJumpToDefinitionDelegate.swift
//  CodeEdit
//
//  Created by CodeEdit on 9/21/26.
//

import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import LanguageServerProtocol

/// Provides language-server powered "Jump to Definition" to the source editor.
///
/// This delegate is installed on every ``CodeFileView``. It forwards definition requests to the
/// language server that manages the document (if any) and maps the returned locations to
/// ``JumpToDefinitionLink`` values. Definitions in the same document are returned as local links
/// so the editor can jump without reopening the file; definitions in other files are opened in the
/// nearest workspace by ``openLink(link:)``. Documents without a running language server, or whose
/// server supports neither `textDocument/definition` nor `textDocument/declaration`, return `nil`.
@MainActor
final class LSPJumpToDefinitionDelegate: JumpToDefinitionDelegate {
    private weak var document: CodeFileDocument?

    @LazyService private var lspService: LSPService

    init(document: CodeFileDocument) {
        self.document = document
    }

    // MARK: - JumpToDefinitionDelegate

    func queryLinks(forRange range: NSRange, textView: TextViewController) async -> [JumpToDefinitionLink]? {
        guard let document,
              let uri = document.languageServerURI,
              let fileURL = document.fileURL,
              let client = lspService.languageClient(forDocument: fileURL),
              let position = textView.textView.lspPositionFrom(offset: range.location) else {
            return nil
        }

        let response: ThreeTypeOption<Location, [Location], [LocationLink]>?
        do {
            try await document.languageServerObjects.textCoordinator.flushPendingChanges()
            try Task.checkCancellation()
            if client.supportsDefinition {
                response = try await client.requestGoToDefinition(for: uri, position: position, bypassCache: true)
            } else if client.supportsDeclaration {
                response = try await client.requestGoToDeclaration(for: uri, position: position)
            } else {
                return nil
            }
            try Task.checkCancellation()
        } catch {
            return nil
        }

        let symbol = queriedSymbol(in: range, textView: textView)
        let links = Self.locations(from: response).compactMap { location in
            link(for: location, currentURI: uri, symbol: symbol, textView: textView)
        }
        return links.isEmpty ? nil : links
    }

    func openLink(link: JumpToDefinitionLink) {
        guard let url = link.url, url.isFileURL else { return }
        let path = url.path(percentEncoded: false)

        // Open the file in the workspace that shares the most path components with it,
        // mirroring how `CodeEditDocumentController` picks a workspace for opened files.
        let workspaces = CodeEditDocumentController.shared.documents.compactMap { $0 as? WorkspaceDocument }
        for workspace in workspaces.sorted(by: {
            ($0.fileURL?.sharedComponents(url) ?? 0) > ($1.fileURL?.sharedComponents(url) ?? 0)
        }) {
            guard let file = workspace.workspaceFileManager?.getFile(path, createIfNotFound: true) else {
                continue
            }
            workspace.editorManager?.openTab(item: file)
            workspace.editorManager?.activeEditor.selectedTab?.cursorPositions = [link.targetRange]
            workspace.showWindows()
            return
        }

        // The file is not inside any open workspace, open it as a standalone document.
        // `targetRange` is already 1-based. The editor applies `openOptions` on load
        // and when they are set after the document is already open.
        CodeEditDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
            guard error == nil, let document = document as? CodeFileDocument else { return }
            document.openOptions = CodeFileDocument.OpenOptions(cursorPositions: [link.targetRange])
        }
    }

    // MARK: - Response Mapping

    /// Normalizes a definition or declaration response into a flat, de-duplicated list of locations.
    /// - Parameter response: The `textDocument/definition` or `textDocument/declaration` response.
    /// - Returns: Target URIs and ranges. `LocationLink` results use their `targetSelectionRange`.
    nonisolated static func locations(
        from response: ThreeTypeOption<Location, [Location], [LocationLink]>?
    ) -> [(uri: String, range: LSPRange)] {
        guard let response else { return [] }
        let raw: [(uri: String, range: LSPRange)]
        switch response {
        case .optionA(let location):
            raw = [(uri: location.uri, range: location.range)]
        case .optionB(let locations):
            raw = locations.map { (uri: $0.uri, range: $0.range) }
        case .optionC(let locationLinks):
            raw = locationLinks.map { (uri: $0.targetUri, range: $0.targetSelectionRange) }
        }

        var seen: Set<String> = []
        return raw.filter { location in
            let key = """
            \(location.uri)#\(location.range.start.line):\(location.range.start.character)
            """
            return seen.insert(key).inserted
        }
    }

    // MARK: - Helpers

    /// The identifier text covered by the queried range, used as the label for multi-result popovers.
    private func queriedSymbol(in range: NSRange, textView: TextViewController) -> String {
        let string = textView.textView.textStorage.string as NSString
        guard range.length > 0, NSMaxRange(range) <= string.length else { return "" }
        return string.substring(with: range)
    }

    /// Builds a link for a target location. Locations in the queried document become local links
    /// (no URL) so the editor moves the cursor directly; others carry a file URL for ``openLink(link:)``.
    private func link(
        for location: (uri: String, range: LSPRange),
        currentURI: String,
        symbol: String,
        textView: TextViewController
    ) -> JumpToDefinitionLink? {
        let label = symbol.isEmpty ? "Definition" : symbol
        if location.uri == currentURI {
            guard let nsRange = textView.textView.nsRangeFrom(lspRange: location.range) else { return nil }
            return JumpToDefinitionLink(
                url: nil,
                targetRange: CursorPosition(range: nsRange),
                typeName: label,
                sourcePreview: "",
                documentation: nil
            )
        }
        guard let url = URL(string: location.uri), url.isFileURL else { return nil }
        return JumpToDefinitionLink(
            url: url,
            targetRange: CursorPosition(
                line: location.range.start.line + 1,
                column: location.range.start.character + 1
            ),
            typeName: label,
            sourcePreview: "",
            documentation: nil
        )
    }
}

private extension LanguageServer {
    /// Whether the server advertised definition support.
    var supportsDefinition: Bool {
        switch serverCapabilities.definitionProvider {
        case .optionA(let supported):
            return supported
        case .optionB:
            return true
        case nil:
            return false
        }
    }

    /// Whether the server advertised declaration support.
    var supportsDeclaration: Bool {
        switch serverCapabilities.declarationProvider {
        case .optionA(let supported):
            return supported
        case .optionB, .optionC:
            return true
        case nil:
            return false
        }
    }
}
