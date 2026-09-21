//
//  LSPSettings.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/11/26.
//

import Foundation

extension SettingsData {
    /// The global settings for language server integration
    struct LSPSettings: Codable, Hashable, SearchableSettingsPage {

        /// A language server binary the user picked manually for an LSP language identifier.
        struct ConfiguredServer: Codable, Hashable {
            /// The absolute path to the language server binary.
            var path: String
            /// The arguments passed to the binary when launching the server.
            var arguments: [String] = []

            init(path: String, arguments: [String] = []) {
                self.path = path
                self.arguments = arguments
            }
        }

        /// Manually configured language servers, keyed by LSP language identifier.
        var servers: [String: ConfiguredServer] = [:]

        /// The search keys
        var searchKeys: [String] {
            [
                "Language Servers",
                "Language Server Protocol",
                "LSP",
                "Detect Servers"
            ]
            .map { NSLocalizedString($0, comment: "") }
        }

        /// Default initializer
        init() {}

        /// Explicit decoder init for setting default values when key is not present in `JSON`
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            self.servers = try container.decodeIfPresent(
                [String: ConfiguredServer].self,
                forKey: .servers
            ) ?? [:]
        }
    }
}
