//
//  AppLanguage.swift
//  CodeEdit
//
//  Created by CodeEdit Developer on 10/22/26.
//

import AppKit

/// The interface language CodeEdit launches with.
///
/// The choice is stored as the app's `AppleLanguages` default, which Foundation reads once at launch,
/// so a change takes effect after CodeEdit restarts. ``system`` removes the override.
enum AppLanguage: String, CaseIterable, Identifiable {
    /// Follow the language order in System Settings.
    case system
    /// English.
    case english = "en"
    /// Simplified Chinese.
    case simplifiedChinese = "zh-Hans"

    private static let defaultsKey = "AppleLanguages"

    var id: String { rawValue }

    /// The name shown in the language picker. Language names are written in their own language.
    var displayName: String {
        switch self {
        case .system:
            return String(localized: "System Default", comment: "Language picker option that follows macOS")
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        }
    }

    /// The language selected in CodeEdit's own defaults, or ``system`` when there is no override.
    static var current: AppLanguage {
        guard let languages = UserDefaults.standard.persistentDomain(
            forName: Bundle.main.bundleIdentifier ?? ""
        )?[defaultsKey] as? [String],
              let first = languages.first else {
            return .system
        }
        return allCases.first { $0 != .system && first.hasPrefix($0.rawValue) } ?? .system
    }

    /// Stores the language for the next launch.
    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        } else {
            UserDefaults.standard.set([rawValue], forKey: Self.defaultsKey)
        }
    }

    /// Relaunches CodeEdit so the new language is loaded.
    static func relaunch() {
        // Wait for this instance to exit before the new one starts, so the two never run side by side.
        // The pid and bundle path are passed as positional arguments, never interpolated into the script.
        let script = "while kill -0 \"$0\" 2>/dev/null; do sleep 0.2; done; open \"$1\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c", script,
            String(ProcessInfo.processInfo.processIdentifier),
            Bundle.main.bundleURL.path
        ]
        try? task.run()
        NSApp.terminate(nil)
    }
}
