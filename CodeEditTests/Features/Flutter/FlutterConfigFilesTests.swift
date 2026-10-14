//
//  FlutterConfigFilesTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation
import Testing
@testable import CodeEdit

@Suite
struct FlutterConfigFilesTests {
    // MARK: - YAML

    @Test
    func readsNestedMappingsSequencesAndFlowCollections() {
        let root = YAMLReader.parse("""
        a:
          b: 1
          list:
            - x
            - 'y'
          inline: [1, "two", {k: v}]
        items:
        - name: first
          value: 1
        - name: second
          nested:
            - deep
        flow: { sdk: flutter, path: "../x" }
        """)
        #expect(root["a"]?["b"]?.string == "1")
        #expect(root["a"]?["list"]?.strings == ["x", "y"])
        #expect(root["a"]?["inline"]?.sequence?.count == 3)
        #expect(root["a"]?["inline"]?.sequence?.last?["k"]?.string == "v")
        let items = root["items"]?.sequence ?? []
        #expect(items.compactMap { $0["name"]?.string } == ["first", "second"])
        #expect(items.last?["nested"]?.strings == ["deep"])
        #expect(root["flow"]?["path"]?.string == "../x")
    }

    @Test
    func readsBlockScalarsAndKeepsLaterKeys() {
        let root = YAMLReader.parse("""
        literal: |
          line one
            indented
        folded: >-
          a
          b
        after: done
        """)
        #expect(root["literal"]?.string == "line one\n  indented")
        #expect(root["folded"]?.string == "a b")
        #expect(root["after"]?.string == "done")
    }

    // MARK: - pubspec

    /// The dependency and asset parts of OmniExam's `pubspec.yaml`.
    static let omniExamPubspec = """
    name: omniexam_app
    description: "OmniExam macOS 客户端"
    publish_to: 'none'
    version: 0.6.0+1

    environment:
      sdk: ^3.13.0
      flutter: 3.47.0

    dependencies:
      archive: ^4.0.9
      flutter:
        sdk: flutter
      flutter_math_fork:
        path: third_party/flutter_math_fork
      pinned:
        git:
          url: https://example.com/pinned.git
          ref: main
      hooks: ^2.0.2

    dev_dependencies:
      flutter_test:
        sdk: flutter
      ffigen: ^19.0.0

    dependency_overrides:
      path: 1.9.0

    flutter:
      uses-material-design: true
      generate: true
      assets:
        - assets/images/
        # 本地 OCR 模型清单
        - assets/ocr/manifest.json
      fonts:
        - family: Source Han Serif SC
          fonts:
            - asset: assets/fonts/SourceHanSerifSC-Regular.otf
              weight: 400
        - family: XITS Math
          fonts:
            - asset: assets/fonts/XITSMath-Regular.otf
    """

    @Test
    func readsDependenciesAssetsAndFonts() {
        let pubspec = PubspecParser.parse(Self.omniExamPubspec)
        #expect(pubspec.name == "omniexam_app")
        #expect(pubspec.description == "OmniExam macOS 客户端")
        #expect(pubspec.publishTo == "none")
        #expect(pubspec.sdkConstraint == "^3.13.0")
        #expect(pubspec.flutterConstraint == "3.47.0")
        #expect(pubspec.dependsOnFlutter)
        #expect(pubspec.dependencies(of: .normal).map(\.name)
                == ["archive", "flutter", "flutter_math_fork", "pinned", "hooks"])
        let byName = Dictionary(uniqueKeysWithValues: pubspec.dependencies.map { ($0.name, $0.source) })
        #expect(byName["archive"] == .hosted("^4.0.9"))
        #expect(byName["flutter_math_fork"] == .path("third_party/flutter_math_fork"))
        #expect(byName["pinned"] == .git(url: "https://example.com/pinned.git", ref: "main", path: nil))
        #expect(byName["flutter_test"] == .sdk("flutter"))
        #expect(pubspec.dependencies(of: .override).map(\.name) == ["path"])
        #expect(pubspec.hasDependency(named: "ffigen"))
        #expect(pubspec.assets == ["assets/images/", "assets/ocr/manifest.json"])
        #expect(pubspec.fontFamilies == ["Source Han Serif SC", "XITS Math"])
        #expect(pubspec.usesMaterialDesign)
        #expect(pubspec.generatesLocalizations)
    }

    // MARK: - analysis_options.yaml and .metadata

    @Test
    func readsAnalysisOptionsInListAndMapForm() {
        let list = AnalysisOptions.parse("""
        analyzer:
          exclude:
            - build/**
            - third_party/**
          language:
            strict-casts: true
            strict-raw-types: false
          errors:
            todo: ignore
        include: package:flutter_lints/flutter.yaml
        linter:
          rules:
            - avoid_print
            - prefer_const_constructors
        """)
        #expect(list.includes == ["package:flutter_lints/flutter.yaml"])
        #expect(list.excludes == ["build/**", "third_party/**"])
        #expect(list.strictModes == ["strict-casts"])
        #expect(list.severityOverrides.map(\.code) == ["todo"])
        #expect(list.enabledRules == ["avoid_print", "prefer_const_constructors"])

        let map = AnalysisOptions.parse("""
        linter:
          rules:
            avoid_print: false
            always_declare_return_types: true
        """)
        #expect(map.enabledRules == ["always_declare_return_types"])
        #expect(map.disabledRules == ["avoid_print"])
    }

    @Test
    func readsMetadata() {
        let metadata = FlutterMetadata.parse("""
        version:
          revision: "ad70ec4617166f1c38e5d2bfd388af71fda14f06"
          channel: "stable"

        project_type: app

        migration:
          platforms:
            - platform: root
              create_revision: ad70ec4617166f1c38e5d2bfd388af71fda14f06
            - platform: windows
              create_revision: ad70ec4617166f1c38e5d2bfd388af71fda14f06
            - platform: macos
              create_revision: ad70ec4617166f1c38e5d2bfd388af71fda14f06
        """)
        #expect(metadata.projectType == "app")
        #expect(metadata.channel == "stable")
        #expect(metadata.platforms == ["windows", "macos"])
    }

    @Test
    func pubResolutionFollowsFileDates() throws {
        try withTempDir { root in
            try "name: x".write(to: root.appending(path: "pubspec.yaml"), atomically: true, encoding: .utf8)
            #expect(PubResolutionState.check(in: root) == .missing)
            let config = root.appending(path: ".dart_tool/package_config.json")
            let folder = config.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "{}".write(to: config, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-60)],
                ofItemAtPath: config.path
            )
            #expect(PubResolutionState.check(in: root) == .outdated)
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(60)],
                ofItemAtPath: config.path
            )
            #expect(PubResolutionState.check(in: root) == .upToDate)
        }
    }

    @Test
    func parsesFlutterDevicesMachineOutput() {
        let devices = FlutterDevice.parse(machineOutput: """
        Waiting for another flutter command to release the startup lock...
        [
          {"name": "macOS", "id": "macos", "isSupported": true, "targetPlatform": "darwin", "emulator": false,
           "sdk": "macOS 26.1"},
          {"name": "Chrome", "id": "chrome", "isSupported": true, "targetPlatform": "web-javascript", "emulator": false}
        ]
        """)
        #expect(devices.map(\.id) == ["macos", "chrome"])
        #expect(devices.first?.buildPlatform == .macos)
        #expect(devices.last?.buildPlatform == .web)
    }
}
