//
//  ExtensionInfo.swift
//  CodeEdit
//
//  Created by Wouter Hennen on 31/12/2022.
//

import AppKit
import CodeEditKit
import ExtensionFoundation

struct ExtensionInfo: Identifiable, Hashable {

    let endpoint: AppExtensionIdentity

    let availableFeatures: [ExtensionKind]

    let isDebug: Bool

    var bundleURL: URL

    var bundle: Bundle?

    var pid: Int32

    var id: String {
        endpoint.bundleIdentifier
    }

    var name: String {
        endpoint.localizedName
    }

    var version: String? {
        bundle?.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    func restart() {
        kill(pid, SIGKILL)
    }

    init(endpoint: AppExtensionIdentity) async throws {
        self.endpoint = endpoint

        let process = try await AppExtensionProcess(configuration: .init(appExtensionIdentity: endpoint))

        let connection = try process.makeXPCConnection()
        connection.remoteObjectInterface = ExtensionInfo.makeRemoteInterface()
        connection.resume()

        defer {
            connection.invalidate()
        }

        self.pid = try await ExtensionInfo.getProcessID(connection)
        self.isDebug = try await ExtensionInfo.getDebugState(connection)
        self.availableFeatures = try await ExtensionInfo.getAvailableFeatures(connection)
        self.bundleURL = try await ExtensionInfo.getBundleURL(connection)
        self.bundle = Bundle(url: bundleURL)
    }
}

// Functions to get basic information about extension
extension ExtensionInfo {
    /// Builds the `XPCWrappable` interface with explicit secure-coding classes for the `(Data?, Error?)` replies,
    /// so Foundation doesn't fall back to an `NSObject` allow-list (which it reports as a fault).
    private static func makeRemoteInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: XPCWrappable.self)
        let replySelectors = [
            #selector(XPCWrappable.getExtensionURL(reply:)),
            #selector(XPCWrappable.getExtensionKinds(reply:)),
            #selector(XPCWrappable.doAction(with:reply:))
        ]
        for selector in replySelectors {
            interface.setClasses(
                NSSet(object: NSData.self) as? Set<AnyHashable> ?? [],
                for: selector,
                argumentIndex: 0,
                ofReply: true
            )
            interface.setClasses(
                NSSet(object: NSError.self) as? Set<AnyHashable> ?? [],
                for: selector,
                argumentIndex: 1,
                ofReply: true
            )
        }
        return interface
    }

    private static func getProcessID(_ connection: NSXPCConnection) async throws -> pid_t {
        try await connection.withContinuation { (service: XPCWrappable, continuation) in
            service.getExtensionProcessIdentifier {
                continuation.resumingHandler($0, .none)
            }
        }
    }

    private static func getDebugState(_ connection: NSXPCConnection) async throws -> Bool {
        try await connection.withContinuation { (service: XPCWrappable, continuation) in
            service.isDebug {
                continuation.resumingHandler($0, .none)
            }
        }
    }

    private static func getAvailableFeatures(_ connection: NSXPCConnection) async throws -> [ExtensionKind] {
        let encodedAvailableFeatures = try await connection.withContinuation { (service: XPCWrappable, continuation) in
            service.getExtensionKinds(reply: continuation.resumingHandler)
        }
        return try JSONDecoder().decode([ExtensionKind].self, from: encodedAvailableFeatures)
    }

    private static func getBundleURL(_ connection: NSXPCConnection) async throws -> URL {
        let bundleURLEncoded = try await connection.withContinuation { (service: XPCWrappable, continuation) in
            service.getExtensionURL(reply: continuation.resumingHandler)
        }

        return try JSONDecoder().decode(URL.self, from: bundleURLEncoded)
    }
}

extension ExtensionInfo {
    /// Bundle identifier of parent app
    var parentBundleIdentifier: String {
        endpoint.bundleIdentifier.split(separator: ".").dropLast().joined(separator: ".")
    }

    var lastPathOfBundleIdentifier: String {
        String(endpoint.bundleIdentifier.split(separator: ".").last!)
    }

    /// Icon of appex folder
    public var icon: NSImage? {
        // TODO: Use icon of extension instead of parent app
        // A way to get the path of an .appex file should be used.
        // Unfortunately, NSWorkspace.shared.urlForApplication only seems to work for .app
        let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: parentBundleIdentifier)
        guard let path else { return nil }

        return NSWorkspace.shared.icon(forFile: path.path)
    }
}
