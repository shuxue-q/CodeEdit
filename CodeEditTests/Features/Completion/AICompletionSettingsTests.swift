//
//  AICompletionSettingsTests.swift
//  CodeEditTests
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import XCTest

@testable import CodeEdit

final class AICompletionSettingsTests: XCTestCase {
    private typealias AISettings = SettingsData.TextEditingSettings.AICompletionSettings

    private func decode(_ json: String) throws -> AISettings {
        try JSONDecoder().decode(AISettings.self, from: Data(json.utf8))
    }

    func testDefaultsAreOffAndAnthropic() {
        let settings = AISettings()
        XCTAssertFalse(settings.enabled)
        XCTAssertEqual(settings.backend, .anthropic)
        XCTAssertEqual(settings.model, "claude-opus-5")
        XCTAssertEqual(settings.baseURL, "")
    }

    func testAnOldSettingsFileWithoutABackendDecodesToAnthropicAndKeepsItsModel() throws {
        let settings = try decode(#"{"enabled": true, "model": "claude-sonnet-5"}"#)
        XCTAssertTrue(settings.enabled)
        XCTAssertEqual(settings.backend, .anthropic)
        XCTAssertEqual(settings.model, "claude-sonnet-5")
        XCTAssertEqual(settings.baseURL, "")
    }

    func testAnEmptyObjectDecodesToDefaults() throws {
        XCTAssertEqual(try decode("{}"), AISettings())
    }

    func testEveryBackendDecodes() throws {
        for kind in AIBackendKind.allCases {
            let json = #"{"enabled": true, "backend": "\#(kind.rawValue)", "model": "m", "baseURL": "u"}"#
            let settings = try decode(json)
            XCTAssertEqual(settings.backend, kind)
            XCTAssertEqual(settings.model, "m")
            XCTAssertEqual(settings.baseURL, "u")
        }
    }

    func testMissingModelAndBaseURLTakeThePerBackendDefaults() throws {
        let openAI = try decode(#"{"backend": "openAI"}"#)
        XCTAssertEqual(openAI.model, "gpt-5")
        XCTAssertEqual(openAI.baseURL, "")
        let compatible = try decode(#"{"backend": "openAICompatible"}"#)
        XCTAssertEqual(compatible.model, "")
        XCTAssertEqual(compatible.baseURL, "http://localhost:11434/v1")
    }

    func testAnUnknownBackendFallsBackToAnthropicInsteadOfFailingTheDecode() throws {
        let settings = try decode(#"{"enabled": true, "backend": "somethingNew", "model": "x"}"#)
        XCTAssertEqual(settings.backend, .anthropic)
        XCTAssertTrue(settings.enabled)
    }

    func testRoundTripPreservesEveryField() throws {
        var settings = AISettings()
        settings.enabled = true
        settings.backend = .openAICompatible
        settings.model = "deepseek-chat"
        settings.baseURL = "https://api.deepseek.com/v1"
        let decoded = try JSONDecoder().decode(AISettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
    }

    func testSettingsFileHoldsNoKeyOrPresetTable() throws {
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(AISettings()), encoding: .utf8))
        XCTAssertFalse(json.lowercased().contains("apikey"))
        XCTAssertFalse(json.contains("presets"))
    }

    func testEachBackendHasItsOwnKeychainEntryAndAnthropicsIsUnchanged() {
        XCTAssertEqual(AISettings.keychainKey(for: .anthropic), "anthropicAPIKey")
        XCTAssertEqual(AISettings.keychainKey(for: .openAI), "openAIAPIKey")
        XCTAssertEqual(AISettings.keychainKey(for: .openAICompatible), "openAICompatibleAPIKey")
        XCTAssertEqual(Set(AIBackendKind.allCases.map { AISettings.keychainKey(for: $0) }).count, 3)
    }

    func testConfigurationUsesTheBaseURLOnlyForTheCompatibleBackend() {
        var settings = AISettings()
        settings.baseURL = "http://localhost:11434/v1"
        XCTAssertNil(settings.configuration(apiKey: "k").baseURL)
        settings.backend = .openAI
        XCTAssertNil(settings.configuration(apiKey: "k").baseURL)
        settings.backend = .openAICompatible
        settings.model = " qwen "
        let configuration = settings.configuration(apiKey: "k")
        XCTAssertEqual(configuration.baseURL?.absoluteString, "http://localhost:11434/v1")
        XCTAssertEqual(configuration.model, "qwen")
        XCTAssertEqual(configuration.apiKey, "k")
    }

    func testPresetsAreWellFormed() {
        XCTAssertFalse(AISettings.presets.isEmpty)
        for preset in AISettings.presets {
            XCTAssertNotNil(URL(string: preset.baseURL), preset.name)
        }
        XCTAssertEqual(Set(AISettings.presets.map(\.id)).count, AISettings.presets.count)
    }
}
