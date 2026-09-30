//
//  LSPCompletionOrigin.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/27/26.
//

import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol

/// The header a completion comes from, when the language server left it off the item.
///
/// Clangd prefixes a label with `•` when accepting the item will insert an include, and with a
/// space when the header is already visible. In the second case it often omits the
/// `From \`<header>\`` line, so the suggestion window has nothing to show as the source.
enum LSPCompletionOrigin {
    /// A qualified completion label split into the scope and the unqualified name.
    struct QualifiedName: Equatable {
        var qualifier: String
        var name: String
    }

    /// One symbol returned by `workspace/symbol`.
    struct Hit: Equatable {
        var name: String
        var containerName: String?
        var uri: String
    }

    /// `true` when documentation or detail already names a header the suggestion window can show.
    static func hasHeader(documentation: String?, detail: String?) -> Bool {
        header(in: documentation) != nil || header(in: detail) != nil
    }

    /// Reads a `From \`<header>\`` or `From <header>` line. Matches the suggestion window's parser.
    static func header(in text: String?) -> String? {
        guard let text else { return nil }
        let patterns = [
            #"From\s+`([^`]+)`"#,
            #"From\s+(<[^>\n]+>)"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = expression.firstMatch(in: text, range: range),
                  match.numberOfRanges > 1,
                  let headerRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            let header = String(text[headerRange])
            if !header.isEmpty {
                return header
            }
        }
        return nil
    }

    /// Strips clangd's include-insertion marker and splits `CLI::adl_detail`.
    static func qualifiedName(from label: String) -> QualifiedName {
        var text = label
        if text.hasPrefix("•") {
            text.removeFirst()
        } else if let next = text.dropFirst().first, text.first == " ", !next.isWhitespace {
            text.removeFirst()
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.range(of: "::", options: .backwards) else {
            return QualifiedName(qualifier: "", name: trimmed)
        }
        return QualifiedName(
            qualifier: String(trimmed[..<separator.lowerBound]),
            name: String(trimmed[separator.upperBound...])
        )
    }

    static func hits(from response: WorkspaceSymbolResponse) -> [Hit] {
        switch response {
        case .optionA(let symbols):
            return symbols.map { Hit(name: $0.name, containerName: $0.containerName, uri: $0.location.uri) }
        case .optionB(let symbols):
            return symbols.compactMap { symbol in
                guard let uri = fileURI(of: symbol.location) else { return nil }
                return Hit(name: symbol.name, containerName: symbol.containerName, uri: uri)
            }
        case nil:
            return []
        }
    }

    /// The declaring file for `label`, when exactly one workspace symbol matches its name and scope.
    static func match(label: String, symbols: [Hit]) -> URL? {
        let qualified = qualifiedName(from: label)
        guard qualified.name.count >= 3 else { return nil }
        let named = symbols.filter { $0.name == qualified.name }
        let scoped = named.filter { containersMatch($0.containerName, qualified.qualifier) }
        let chosen: Hit?
        if scoped.count == 1 {
            chosen = scoped[0]
        } else if qualified.qualifier.isEmpty, named.count == 1 {
            chosen = named[0]
        } else {
            chosen = nil
        }
        guard let chosen, let url = URL(string: chosen.uri), url.isFileURL else { return nil }
        return url
    }

    /// Include spelling such as `<CLI/CLI.hpp>`, or the file name when it is not under `include/`.
    static func headerSpelling(for fileURL: URL) -> String {
        let path = fileURL.path
        for marker in ["/include/", "/Include/"] {
            if let range = path.range(of: marker, options: .backwards) {
                let relative = String(path[range.upperBound...])
                if !relative.isEmpty {
                    return "<\(relative)>"
                }
            }
        }
        return fileURL.lastPathComponent
    }

    /// Header to show for `label`, or `nil` when the lookup is ambiguous or has no file.
    static func declaringHeader(for label: String, response: WorkspaceSymbolResponse) -> String? {
        guard let url = match(label: label, symbols: hits(from: response)) else { return nil }
        return headerSpelling(for: url)
    }

    private static func containersMatch(_ container: String?, _ qualifier: String) -> Bool {
        let lhs = (container ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rhs = qualifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return lhs == rhs
    }

    private static func fileURI(of location: TwoTypeOption<Location, TextDocumentIdentifier>?) -> String? {
        switch location {
        case .optionA(let location):
            return location.uri
        case .optionB(let document):
            return document.uri
        case nil:
            return nil
        }
    }
}

extension LSPCompletionEntry {
    /// Appends a `From \`header\`` line so the suggestion window can show where the symbol is declared.
    func withOriginHeader(_ header: String) -> LSPCompletionEntry {
        let line = "From `\(header)`"
        let documentation: TwoTypeOption<String, MarkupContent>
        switch item.documentation {
        case .optionA(let string):
            documentation = .optionA(string.isEmpty ? line : string + "\n\n" + line)
        case .optionB(let markup):
            let value = markup.value.isEmpty ? line : markup.value + "\n\n" + line
            documentation = .optionB(MarkupContent(kind: markup.kind, value: value))
        case nil:
            documentation = .optionA(line)
        }
        return LSPCompletionEntry(
            item: CompletionItem(
                label: item.label,
                kind: item.kind,
                detail: item.detail,
                documentation: documentation,
                deprecated: item.deprecated,
                preselect: item.preselect,
                sortText: item.sortText,
                filterText: item.filterText,
                insertText: item.insertText,
                insertTextFormat: item.insertTextFormat,
                textEdit: item.textEdit,
                additionalTextEdits: item.additionalTextEdits,
                commitCharacters: item.commitCharacters,
                command: item.command,
                data: item.data
            )
        )
    }
}

extension LSPCompletionProvider {
    /// Resolves a completion item, filling in documentation and its declaring header when missing.
    func resolveIfSupported(
        _ item: CompletionItem,
        client: LSPService.LanguageServerType
    ) async -> CompletionItem {
        guard client.serverCapabilities.completionProvider?.resolveProvider == true else {
            return item
        }
        guard let resolved = try? await client.requestCompletionResolve(item) else {
            return item
        }
        return resolved
    }

    /// Appends a `From \`header\`` documentation line when the item doesn't already name one.
    func attachDeclaringHeader(
        to item: CompletionItem,
        client: LSPService.LanguageServerType
    ) async -> CompletionItem {
        let entry = LSPCompletionEntry(item: item)
        guard !LSPCompletionOrigin.hasHeader(documentation: entry.documentation, detail: entry.detail) else {
            return item
        }
        let name = LSPCompletionOrigin.qualifiedName(from: entry.label).name
        guard name.count >= 3,
              client.supportsWorkspaceSymbols,
              let response = try? await client.requestWorkspaceSymbols(query: name) else {
            return item
        }
        guard let header = LSPCompletionOrigin.declaringHeader(for: entry.label, response: response) else {
            return item
        }
        return entry.withOriginHeader(header).item
    }
}
