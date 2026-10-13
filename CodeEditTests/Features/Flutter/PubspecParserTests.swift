//
//  PubspecParserTests.swift
//  CodeEditTests
//
//  Created by CodeEdit contributors on 10/13/26.
//

import Foundation
import Testing
@testable import CodeEdit

@Suite
struct PubspecParserTests {
    @Test
    func readsAppNameVersionAndFlutterDependency() {
        let pubspec = PubspecParser.parse("""
        name: omniexam_app
        description: "OmniExam client # not a comment"
        publish_to: 'none'
        version: 0.6.0+1 # build 1

        environment:
          sdk: ^3.13.0
          flutter: 3.47.0

        dependencies:
          archive: ^4.0.9
          flutter:
            sdk: flutter
          flutter_localizations:
            sdk: flutter

        flutter:
          uses-material-design: true
          assets:
            - assets/images/
        """)
        #expect(pubspec.name == "omniexam_app")
        #expect(pubspec.version == "0.6.0+1")
        #expect(pubspec.dependsOnFlutter)
        #expect(pubspec.ffiPluginPlatforms.isEmpty)
    }

    @Test
    func readsFFIPluginPlatforms() {
        let pubspec = PubspecParser.parse("""
        name: "native_add"
        version: '0.0.1'

        dependencies:
          ffi: ^2.1.0
          flutter: { sdk: flutter }

        flutter:
          plugin:
            platforms:
              android:
                ffiPlugin: true
              ios:
                ffiPlugin: false
              macos: { ffiPlugin: true }
              linux:
                pluginClass: NativeAddPlugin
                ffiPlugin: true
        """)
        #expect(pubspec.name == "native_add")
        #expect(pubspec.version == "0.0.1")
        #expect(pubspec.dependsOnFlutter)
        #expect(pubspec.ffiPluginPlatforms == ["android", "macos", "linux"])
    }

    @Test
    func ignoresFlutterKeysOutsideDependencies() {
        let pubspec = PubspecParser.parse("""
        name: pure_dart
        environment:
          flutter:
            sdk: flutter
        dev_dependencies:
          flutter:
            sdk: flutter
        """)
        #expect(pubspec.name == "pure_dart")
        #expect(!pubspec.dependsOnFlutter)
    }

    @Test
    func skipsBlockScalarsAndComments() {
        let pubspec = PubspecParser.parse("""
        # name: commented
        description: |
          name: inside block scalar
          dependencies:
            flutter:
              sdk: flutter
        name: real_name
        dependencies:
        #  flutter:
        #    sdk: flutter
          path: ^1.9.1
        """)
        #expect(pubspec.name == "real_name")
        #expect(!pubspec.dependsOnFlutter)
    }

    @Test
    func toleratesCRLFAndDocumentMarker() {
        let text = "---\r\nname: crlf_app\r\ndependencies:\r\n  flutter:\r\n    sdk: flutter\r\n"
        let pubspec = PubspecParser.parse(text)
        #expect(pubspec.name == "crlf_app")
        #expect(pubspec.dependsOnFlutter)
    }

    @Test
    func emptyInputHasNoKeys() {
        #expect(PubspecParser.parse("") == Pubspec())
    }
}
