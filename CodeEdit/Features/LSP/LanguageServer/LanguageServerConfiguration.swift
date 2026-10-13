//
//  LanguageServerConfiguration.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import LanguageServerProtocol

/// Per-language settings CodeEdit hands to a language server: the `initializationOptions` of the
/// `initialize` request, and the answers to the server's `workspace/configuration` requests.
///
/// Servers without an entry get the same values as before per-language settings existed: an empty
/// `initializationOptions` array and `null` for every requested configuration section.
enum LanguageServerConfiguration {
    /// The most completion items the Dart analysis server returns for one request.
    ///
    /// The server's own default is 2000, which is about 1 MB of JSON for a one-letter prefix in a
    /// Flutter project, and it marks every capped list `isIncomplete`. Fewer, better-ranked items
    /// keep decoding, mapping and ranking quick while typing.
    static let dartMaxCompletionItems = 500

    /// The `initializationOptions` sent with the `initialize` request.
    /// - Parameter languageId: The LSP language identifier the server is started for.
    /// - Returns: The options for that language's server.
    static func initializationOptions(for languageId: String) -> LSPAny {
        switch languageId {
        case "dart":
            return .hash([
                // Analyze only the packages that contain open files, not every pubspec under the root.
                "onlyAnalyzeProjectsWithOpenFiles": .bool(true),
                // Offer symbols from libraries the file does not import yet; resolving such an item adds the import.
                "suggestFromUnimportedLibraries": .bool(true),
                // CodeEdit shows none of these, so don't have the server compute and send them on every edit.
                "closingLabels": .bool(false),
                "outline": .bool(false),
                "flutterOutline": .bool(false)
            ])
        default:
            return .array([])
        }
    }

    /// The answer to a `workspace/configuration` request: one value per requested item, in order.
    /// - Parameters:
    ///   - params: The items the server asked for.
    ///   - languageId: The LSP language identifier of the asking server.
    /// - Returns: The configuration values, `null` for sections CodeEdit has no settings for.
    static func workspaceConfiguration(for params: ConfigurationParams, languageId: String) -> [LSPAny] {
        params.items.map { workspaceConfiguration(section: $0.section, languageId: languageId) }
    }

    /// The value of one configuration section.
    /// - Parameters:
    ///   - section: The requested section, such as `dart`.
    ///   - languageId: The LSP language identifier of the asking server.
    /// - Returns: The section's settings, or `null` when CodeEdit has none for it.
    static func workspaceConfiguration(section: String?, languageId: String) -> LSPAny {
        switch (languageId, section) {
        case ("dart", "dart"):
            return .hash([
                "maxCompletionItems": .number(Double(dartMaxCompletionItems))
            ])
        default:
            return .null
        }
    }
}
