//
//  CompletionBehaviorSettings.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import Foundation

extension SettingsData.TextEditingSettings {
    /// Settings for what accepting a completion does beyond replacing the typed prefix.
    struct CompletionBehaviorSettings: Codable, Hashable {
        /// Whether the extra edits a server attaches to an item (`additionalTextEdits`, for example
        /// clangd's automatic `#include`) are applied together with the item.
        var applyAdditionalEdits: Bool = true

        /// Whether accepting a function or method inserts `()`, putting the caret between them when
        /// the function takes parameters.
        var insertParenthesesForFunctions: Bool = true

        /// Whether typing a commit character (`(`, `.`, `;`, …) accepts the highlighted item and
        /// then inserts the character.
        var commitCharactersEnabled: Bool = true

        /// Default initializer.
        init() {}

        /// Explicit decoder init for setting default values when a key is not present in `JSON`.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.applyAdditionalEdits = try container.decodeIfPresent(
                Bool.self,
                forKey: .applyAdditionalEdits
            ) ?? true
            self.insertParenthesesForFunctions = try container.decodeIfPresent(
                Bool.self,
                forKey: .insertParenthesesForFunctions
            ) ?? true
            self.commitCharactersEnabled = try container.decodeIfPresent(
                Bool.self,
                forKey: .commitCharactersEnabled
            ) ?? true
        }
    }
}
