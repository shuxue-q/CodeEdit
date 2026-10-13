//
//  FlutterSDK.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

/// The Flutter SDK found through the `flutter` command on the user's login-shell `PATH`.
struct FlutterSDK: Equatable, Sendable {
    /// The SDK checkout, the folder holding `bin/flutter`.
    let rootDirectory: URL
    /// The Flutter framework version, such as `3.47.0`.
    var version: String?
    /// The release channel, such as `stable`, when the SDK records it.
    var channel: String?
    /// The bundled Dart SDK version, when the SDK records it.
    var dartVersion: String?

    /// Locates `flutter` in the login shell and reads the SDK it belongs to.
    ///
    /// Spawns the user's login shell; call it off the main actor.
    /// - Returns: The SDK, or `nil` when `flutter` is not on `PATH`.
    static func locate() -> Self? {
        guard let flutter = LanguageServerDetector.locateExecutables(["flutter"])["flutter"] else { return nil }
        return sdk(forExecutable: URL(filePath: flutter))
    }

    /// Reads the SDK a `flutter` executable belongs to, following symlinks such as
    /// `~/.local/bin/flutter -> <sdk>/bin/flutter`.
    /// - Parameter executable: The `flutter` command found on `PATH`.
    /// - Returns: The SDK, or `nil` when the executable is not inside an SDK's `bin` folder.
    static func sdk(forExecutable executable: URL) -> Self? {
        let resolved = executable.resolvingSymlinksInPath().standardizedFileURL
        let binDirectory = resolved.deletingLastPathComponent()
        guard binDirectory.lastPathComponent == "bin" else { return nil }
        let root = binDirectory.deletingLastPathComponent()
        guard FileManager.default.isExecutableFile(atPath: root.appending(path: "bin/flutter").path) else {
            return nil
        }
        var sdk = Self(rootDirectory: root)
        sdk.readVersion()
        return sdk
    }

    /// Reads the version from `<sdk>/version`, or from `bin/cache/flutter.version.json`, which
    /// recent SDKs write instead.
    private mutating func readVersion() {
        if let json = try? Data(contentsOf: rootDirectory.appending(path: "bin/cache/flutter.version.json")),
           let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] {
            version = (object["flutterVersion"] ?? object["frameworkVersion"]) as? String
            channel = object["channel"] as? String
            dartVersion = object["dartSdkVersion"] as? String
        }
        if let text = try? String(contentsOf: rootDirectory.appending(path: "version"), encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { version = trimmed }
        }
    }
}
