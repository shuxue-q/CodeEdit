//
//  FlutterDevice.swift
//  CodeEdit
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation

/// A device `flutter run -d` can target, as listed by `flutter devices --machine`.
struct FlutterDevice: Equatable, Hashable, Sendable, Identifiable, Decodable {
    var id: String
    var name: String
    /// Such as `darwin`, `ios`, `android-arm64` or `web-javascript`.
    var targetPlatform: String?
    var isSupported = true
    var isEmulator = false
    /// The OS description, such as `macOS 26.1`.
    var sdk: String?

    enum CodingKeys: String, CodingKey {
        case id, name, targetPlatform, isSupported, sdk
        case isEmulator = "emulator"
    }

    init(id: String, name: String, targetPlatform: String? = nil, sdk: String? = nil) {
        self.id = id
        self.name = name
        self.targetPlatform = targetPlatform
        self.sdk = sdk
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? id
        targetPlatform = try? container.decode(String.self, forKey: .targetPlatform)
        isSupported = (try? container.decode(Bool.self, forKey: .isSupported)) ?? true
        isEmulator = (try? container.decode(Bool.self, forKey: .isEmulator)) ?? false
        sdk = try? container.decode(String.self, forKey: .sdk)
    }

    /// The device used when none is chosen: the Mac itself.
    static let macOS = Self(id: "macos", name: "macOS", targetPlatform: "darwin")

    /// The `flutter build` platform for the device, when it maps onto one.
    var buildPlatform: FlutterPlatform? {
        switch targetPlatform {
        case "darwin": .macos
        case let platform? where platform.hasPrefix("ios"): .ios
        case let platform? where platform.hasPrefix("android"): .android
        case let platform? where platform.hasPrefix("web"): .web
        case let platform? where platform.hasPrefix("linux"): .linux
        case let platform? where platform.hasPrefix("windows"): .windows
        default: nil
        }
    }

    /// Parses the output of `flutter devices --machine`, which may be preceded by log lines.
    static func parse(machineOutput: String) -> [Self] {
        guard let start = machineOutput.firstIndex(of: "["),
              let end = machineOutput.lastIndex(of: "]"),
              start < end else { return [] }
        let json = Data(machineOutput[start...end].utf8)
        return (try? JSONDecoder().decode([Self].self, from: json)) ?? []
    }
}
