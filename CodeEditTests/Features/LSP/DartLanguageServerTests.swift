//
//  DartLanguageServerTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation
import Testing
import CodeEditSourceEditor
import LanguageServerProtocol
@testable import CodeEdit

/// Locating the Dart analysis server and the per-language settings it is started with.
@Suite
struct DartLanguageServerTests {
    // MARK: - Fake SDK layouts

    /// Writes an executable shell script at `url`, creating its parent directories.
    private func makeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// Creates `link` as a symlink to `target`, creating its parent directories.
    private func makeSymlink(at link: URL, to target: URL) throws {
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    }

    /// A Flutter SDK under `root/flutter` whose `flutter` and `dart` launchers are linked from `root/localbin`,
    /// the layout of `~/.local/bin` pointing into `~/.local/share/flutter`.
    private struct FlutterLayout {
        let flutterLink: URL
        let dartLink: URL
        let bundledDart: URL
    }

    private func makeFlutterLayout(in root: URL, withDartCache: Bool = true) throws -> FlutterLayout {
        let sdkBin = root.appending(path: "flutter/bin")
        let launcher = sdkBin.appending(path: "flutter")
        try makeExecutable(at: launcher)
        try makeExecutable(at: sdkBin.appending(path: "dart"))
        let bundledDart = sdkBin.appending(path: "cache/dart-sdk/bin/dart")
        if withDartCache {
            try makeExecutable(at: bundledDart)
        }
        let flutterLink = root.appending(path: "localbin/flutter")
        let dartLink = root.appending(path: "localbin/dart")
        try makeSymlink(at: flutterLink, to: launcher)
        // On some machines `dart` links to the `flutter` launcher, which dispatches on its own name.
        try makeSymlink(at: dartLink, to: launcher)
        return FlutterLayout(flutterLink: flutterLink, dartLink: dartLink, bundledDart: bundledDart)
    }

    /// The same file as `path`, compared with symlinks (such as `/var` → `/private/var`) resolved.
    private func canonical(_ path: String?) -> String? {
        path.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
    }

    // MARK: - Detection

    @Test
    func dartServerIsSupportedWithLanguageServerArguments() throws {
        let server = try #require(LanguageServerDetector.supportedServers.first { $0.executable == "dart" })
        #expect(server.languageIds == ["dart"])
        #expect(server.arguments == ["language-server", "--protocol=lsp", "--client-id=codeedit"])
        #expect(LanguageServerDetector.supportedLanguageIds.contains("dart"))
    }

    @Test
    func flutterOnPathResolvesToBundledDart() throws {
        try withTempDir { root in
            let layout = try makeFlutterLayout(in: root)
            let resolved = LanguageServerDetector.resolveDartExecutable(
                flutterPath: layout.flutterLink.path,
                dartPath: layout.dartLink.path
            )
            #expect(canonical(resolved) == canonical(layout.bundledDart.path))
        }
    }

    @Test
    func dartLauncherAloneResolvesToBundledDart() throws {
        try withTempDir { root in
            let layout = try makeFlutterLayout(in: root)
            let resolved = LanguageServerDetector.resolveDartExecutable(
                flutterPath: nil,
                dartPath: layout.dartLink.path
            )
            #expect(canonical(resolved) == canonical(layout.bundledDart.path))
        }
    }

    @Test
    func missingDartCacheFallsBackToDartOnPath() throws {
        try withTempDir { root in
            let layout = try makeFlutterLayout(in: root, withDartCache: false)
            let resolved = LanguageServerDetector.resolveDartExecutable(
                flutterPath: layout.flutterLink.path,
                dartPath: layout.dartLink.path
            )
            #expect(resolved == layout.dartLink.path)
        }
    }

    @Test
    func standaloneDartSdkIsUsedAsFound() throws {
        try withTempDir { root in
            let dart = root.appending(path: "dart-sdk/bin/dart")
            try makeExecutable(at: dart)
            #expect(LanguageServerDetector.resolveDartExecutable(flutterPath: nil, dartPath: dart.path) == dart.path)
        }
    }

    @Test
    func flutterWithoutDartCacheAndNoDartIsNotFound() throws {
        try withTempDir { root in
            let layout = try makeFlutterLayout(in: root, withDartCache: false)
            let flutterOnly = LanguageServerDetector.resolveDartExecutable(
                flutterPath: layout.flutterLink.path,
                dartPath: nil
            )
            #expect(flutterOnly == nil)
            #expect(LanguageServerDetector.resolveDartExecutable(flutterPath: nil, dartPath: nil) == nil)
        }
    }

    @Test
    func otherServersUseTheirPathEntry() throws {
        let clangd = try #require(LanguageServerDetector.supportedServers.first { $0.executable == "clangd" })
        let located = ["clangd": "/usr/bin/clangd", "flutter": "/nonexistent/flutter/bin/flutter"]
        #expect(LanguageServerDetector.executablePath(for: clangd, located: located) == "/usr/bin/clangd")
    }

    // MARK: - Initialization options

    @Test
    func dartInitializationOptions() {
        let expected: LSPAny = .hash([
            "onlyAnalyzeProjectsWithOpenFiles": .bool(true),
            "suggestFromUnimportedLibraries": .bool(true),
            "closingLabels": .bool(false),
            "outline": .bool(false),
            "flutterOutline": .bool(false)
        ])
        #expect(LanguageServerConfiguration.initializationOptions(for: "dart") == expected)
    }

    @Test(arguments: ["c", "cpp", "objective-c", "cmake"])
    func otherLanguagesKeepEmptyInitializationOptions(languageId: String) {
        #expect(LanguageServerConfiguration.initializationOptions(for: languageId) == .array([]))
    }

    @Test
    func initializeParamsCarryLanguageOptionsAndResolvableImports() async throws {
        let params = try await LanguageServer<CodeFileDocument>.getInitParams(
            languageId: "dart",
            workspacePath: "/tmp/project"
        )()
        #expect(params.initializationOptions == LanguageServerConfiguration.initializationOptions(for: "dart"))
        // Dart rejects an `initialize` request without the `processId` key.
        #expect(params.processId == Int(ProcessInfo.processInfo.processIdentifier))
        let completion = try #require(params.capabilities.textDocument?.completion)
        // A dynamically registered completion provider would never reach `serverCapabilities`.
        #expect(completion.dynamicRegistration == false)
        let properties = completion.completionItem?.resolveSupport?.properties ?? []
        #expect(properties.contains("additionalTextEdits"))
        #expect(properties.contains("documentation"))

        let cppParams = try await LanguageServer<CodeFileDocument>.getInitParams(
            languageId: "cpp",
            workspacePath: "/tmp/project"
        )()
        #expect(cppParams.initializationOptions == .array([]))
    }

    // MARK: - Workspace configuration

    @Test
    func dartSectionLimitsCompletionItems() {
        let params = ConfigurationParams(items: [
            ConfigurationItem(scopeUri: nil, section: "dart"),
            ConfigurationItem(scopeUri: nil, section: "editor")
        ])
        let values = LanguageServerConfiguration.workspaceConfiguration(for: params, languageId: "dart")
        let limit = Double(LanguageServerConfiguration.dartMaxCompletionItems)
        #expect(values == [.hash(["maxCompletionItems": .number(limit)]), .null])
    }

    @Test
    func otherServersGetNullConfiguration() {
        let params = ConfigurationParams(items: [ConfigurationItem(scopeUri: nil, section: "dart")])
        #expect(LanguageServerConfiguration.workspaceConfiguration(for: params, languageId: "cpp") == [.null])
    }

    // MARK: - Semantic tokens

    /// The legend the Dart analysis server (Dart 3.13) sends, with the capture each type is styled with.
    @Test
    func dartTokenTypesMapToCaptures() {
        let expected: [(String, CaptureName?)] = [
            ("annotation", .typeAlternate),
            ("class", .type),
            ("comment", .comment),
            ("method", .method),
            ("variable", .variable),
            ("parameter", .parameter),
            ("enum", .type),
            ("enumMember", .constant),
            ("type", .type),
            ("source", nil),
            ("property", .property),
            ("keyword", .keyword),
            ("label", .label),
            ("namespace", .namespace),
            ("boolean", .boolean),
            ("number", .number),
            ("string", .string),
            ("function", .function),
            ("typeParameter", .type)
        ]
        for (tokenType, capture) in expected {
            #expect(SemanticTokenMap.captureName(forTokenType: tokenType) == capture, "\(tokenType)")
        }
    }
}
