//
//  CodeFormatStyle.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 9/28/26.
//

import Foundation

extension SettingsData.TextEditingSettings {

    /// A clang-format style used by Format Code.
    ///
    /// Built-in cases map to clang-format's `-style=` names. ``custom`` reads the nearest
    /// `.clang-format` or `_clang-format` file, walking up from the open file.
    enum CodeFormatStyle: String, Codable, Hashable, CaseIterable {
        case llvm = "LLVM"
        case google = "Google"
        case chromium = "Chromium"
        case mozilla = "Mozilla"
        case webKit = "WebKit"
        case microsoft = "Microsoft"
        case gnu = "GNU"
        case custom = "Custom"

        /// The name shown in Settings.
        var displayName: String {
            rawValue
        }
    }
}
