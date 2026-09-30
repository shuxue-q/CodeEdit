//
//  CEWorkspaceSettingsData+NavigatorSettings.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/30/26.
//

import Foundation

/// What the project navigator shows for a workspace, persisted under the `navigator` key of
/// `.codeedit/settings.json`.
struct NavigatorSettings: Codable, Equatable {
    /// Shows files and folders whose names start with a dot, such as `.git` or `.clang-format`.
    var showHiddenFiles: Bool = false
    /// Glob patterns for files and folders hidden from the navigator. A pattern containing `/`
    /// matches the path relative to the workspace root; one ending in `/` matches folders only.
    var excludedPatterns: [String] = []

    init() {}

    enum CodingKeys: CodingKey {
        case showHiddenFiles, excludedPatterns
    }

    /// Explicit decoder init for setting default values when key is not present in `JSON`
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showHiddenFiles = try container.decodeIfPresent(Bool.self, forKey: .showHiddenFiles) ?? false
        excludedPatterns = try container.decodeIfPresent([String].self, forKey: .excludedPatterns) ?? []
    }

    func isEmpty() -> Bool {
        !showHiddenFiles && excludedPatterns.isEmpty
    }
}
