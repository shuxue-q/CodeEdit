//
//  LanguageServerDocument.swift
//  CodeEdit
//
//  Created by Khan Winter on 2/12/25.
//

import AppKit
import CodeEditLanguages
import CodeEditSourceEditor

/// A set of properties a language server sets when a document is registered.
struct LanguageServerDocumentObjects<DocumentType: LanguageServerDocument> {
    var textCoordinator: LSPContentCoordinator<DocumentType> = LSPContentCoordinator()
    // swiftlint:disable:next line_length
    var highlightProvider: SemanticTokenHighlightProvider<SemanticTokenStorage, DocumentType> = SemanticTokenHighlightProvider()
    /// Provides language-server completions to the editor's suggestion window.
    /// Created by ``CodeFileView`` so it exists before a language server has started.
    var completionDelegate: (any CodeSuggestionDelegate)?

    @MainActor
    func setUp(server: LanguageServer<DocumentType>, document: DocumentType) {
        textCoordinator.setUp(server: server, document: document)
        highlightProvider.setUp(server: server, document: document)
    }
}

/// A protocol that allows a language server to register objects on a text document.
protocol LanguageServerDocument: AnyObject {
    var content: NSTextStorage? { get }
    var languageServerURI: String? { get }
    var languageServerObjects: LanguageServerDocumentObjects<Self> { get set }
    func getLanguage() -> CodeLanguage
}

extension LanguageServerDocument {
    /// The LSP language identifier for this document, or `nil` if no known language server supports it.
    ///
    /// Most languages resolve through ``CodeLanguage/lspLanguageId``. Languages without a
    /// tree-sitter representation in `CodeEditLanguages` (such as CMake) are detected by
    /// file name instead.
    var lspLanguageId: String? {
        if let uri = languageServerURI,
           uri.hasSuffix("/CMakeLists.txt") || uri.lowercased().hasSuffix(".cmake") {
            return "cmake"
        }
        return getLanguage().lspLanguageId
    }
}
