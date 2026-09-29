//
//  AICompletionSettings.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import Foundation

extension SettingsData.TextEditingSettings {
    /// Settings for the opt-in Claude-powered AI completion source.
    ///
    /// The API key is never persisted here; it is stored in the Keychain under
    /// ``AICompletionSettings/keychainKey`` and read by `ClaudeCompletionProvider`.
    struct AICompletionSettings: Codable, Hashable {
        /// The Keychain key the Anthropic API key is stored under.
        static let keychainKey = "anthropicAPIKey"

        /// Whether the AI completion source is enabled. Off by default: surrounding code is
        /// only sent to Anthropic once the user opts in.
        var enabled: Bool = false
        /// The Claude model used for completions.
        var model: String = "claude-opus-5"

        /// Default initializer.
        init() {}

        /// Explicit decoder init for setting default values when a key is not present in `JSON`.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            self.model = try container.decodeIfPresent(String.self, forKey: .model) ?? "claude-opus-5"
        }
    }
}
