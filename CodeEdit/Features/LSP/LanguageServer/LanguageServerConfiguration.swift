//
//  LanguageServerConfiguration.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation
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

    /// The `workspace/configuration` section rust-analyzer asks for.
    static let rustAnalyzerSection = "rust-analyzer"

    /// Languages whose servers get a success reply to `window/workDoneProgress/create`.
    ///
    /// rust-analyzer reports its long first indexing through progress tokens and expects each `create`
    /// request answered. The `$/progress` notifications that follow are decoded and dropped without a log.
    /// Other servers' requests stay unanswered, which keeps them from streaming progress CodeEdit does not
    /// show.
    static let workDoneProgressLanguageIds: Set<String> = ["rust"]

    /// Languages whose servers are told about saved documents with `textDocument/didSave`.
    ///
    /// rust-analyzer runs `cargo check` on save (`checkOnSave`) and publishes its diagnostics then; without
    /// the notification they would never follow the code after the first check.
    static let didSaveLanguageIds: Set<String> = ["rust"]

    /// The `initializationOptions` for a server started in a workspace.
    ///
    /// For rust-analyzer this adds the Cargo projects below the workspace root as `linkedProjects` (see
    /// ``CargoProject/linkedProjects(in:)``), which reads the file system: call it off the main actor.
    /// - Parameters:
    ///   - languageId: The LSP language identifier the server is started for.
    ///   - workspacePath: The root of the workspace the server works in.
    /// - Returns: The options for that language's server.
    static func initializationOptions(for languageId: String, workspacePath: String) -> LSPAny {
        guard languageId == "rust" else {
            return initializationOptions(for: languageId)
        }
        let linkedProjects = CargoProject.linkedProjects(in: URL(fileURLWithPath: workspacePath))
        return rustAnalyzerOptions(linkedProjects: linkedProjects.map(\.path))
    }

    /// rust-analyzer's settings: `cargo check` diagnostics, call snippets with the parameter names filled
    /// in, and the server watching files itself, since CodeEdit sends no `workspace/didChangeWatchedFiles`.
    /// - Parameter linkedProjects: Paths of `Cargo.toml` files the server would not discover from the
    ///   workspace root. Left out when empty.
    /// - Returns: The options, in the shape of rust-analyzer's `rust-analyzer` configuration section.
    static func rustAnalyzerOptions(linkedProjects: [String]) -> LSPAny {
        var options: [String: LSPAny] = [
            "checkOnSave": .bool(true),
            "check": .hash(["command": .string("check")]),
            "completion": .hash(["callable": .hash(["snippets": .string("fill_arguments")])]),
            "files": .hash(["watcher": .string("server")])
        ]
        if !linkedProjects.isEmpty {
            options["linkedProjects"] = .array(linkedProjects.map { .string($0) })
        }
        return .hash(options)
    }

    /// The `initializationOptions` sent with the `initialize` request, for options that do not depend on
    /// the workspace.
    /// - Parameter languageId: The LSP language identifier the server is started for.
    /// - Returns: The options for that language's server.
    static func initializationOptions(for languageId: String) -> LSPAny {
        switch languageId {
        case "rust":
            return rustAnalyzerOptions(linkedProjects: [])
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
    ///   - initializationOptions: The options the server was started with. rust-analyzer replaces its
    ///     whole configuration with the answer, so it gets these back, `linkedProjects` included.
    /// - Returns: The configuration values, `null` for sections CodeEdit has no settings for.
    static func workspaceConfiguration(
        for params: ConfigurationParams,
        languageId: String,
        initializationOptions: LSPAny = .null
    ) -> [LSPAny] {
        params.items.map {
            workspaceConfiguration(
                section: $0.section,
                languageId: languageId,
                initializationOptions: initializationOptions
            )
        }
    }

    /// The value of one configuration section.
    /// - Parameters:
    ///   - section: The requested section, such as `dart`.
    ///   - languageId: The LSP language identifier of the asking server.
    ///   - initializationOptions: The options the server was started with.
    /// - Returns: The section's settings, or `null` when CodeEdit has none for it.
    static func workspaceConfiguration(
        section: String?,
        languageId: String,
        initializationOptions: LSPAny = .null
    ) -> LSPAny {
        switch (languageId, section) {
        case ("dart", "dart"):
            return .hash([
                "maxCompletionItems": .number(Double(dartMaxCompletionItems))
            ])
        case ("rust", rustAnalyzerSection):
            if case .hash = initializationOptions {
                return initializationOptions
            }
            return self.initializationOptions(for: "rust")
        default:
            return .null
        }
    }
}
