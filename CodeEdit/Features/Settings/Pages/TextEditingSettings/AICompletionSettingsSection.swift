//
//  AICompletionSettingsSection.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 10/9/26.
//

import SwiftUI

/// The AI completion rows of the `Text Editing` settings page: the opt-in toggle, the provider, its base
/// URL, model and API key, and a connection test.
///
/// Each provider has its own Keychain entry. Switching provider swaps the key field to that entry.
struct AICompletionSettingsSection: View {
    typealias AISettings = SettingsData.TextEditingSettings.AICompletionSettings

    @Binding var settings: AISettings

    @State private var apiKey: String = ""
    @State private var isTesting = false
    @State private var testResult: AICompletionConnectionResult?

    private let keychain = CodeEditKeychain()

    var body: some View {
        Group {
            Toggle(isOn: $settings.enabled) {
                Text("AI Completions")
                Text("Suggests completions using a cloud model.")
            }
            providerPicker
            if settings.backend == .openAICompatible {
                baseURLField
            }
            modelField
            apiKeyField
            testConnection
            Text(
                "When enabled, the code surrounding your cursor is sent to \(settings.backend.displayName) "
                + "to generate suggestions."
            )
            .foregroundColor(.secondary)
        }
        .onAppear { apiKey = keychain.get(AISettings.keychainKey(for: settings.backend)) ?? "" }
    }

    @ViewBuilder private var providerPicker: some View {
        Picker("Provider", selection: providerBinding) {
            ForEach(AIBackendKind.allCases, id: \.self) { kind in
                Text(kind.displayName).tag(kind)
            }
        }
        .disabled(!settings.enabled)
    }

    @ViewBuilder private var baseURLField: some View {
        HStack {
            TextField("Base URL", text: $settings.baseURL, prompt: Text(AIBackendKind.openAICompatible.defaultBaseURL))
                .onChange(of: settings.baseURL) { testResult = nil }
            Menu("Presets") {
                ForEach(AISettings.presets) { preset in
                    Button(preset.name) { apply(preset) }
                }
            }
            .fixedSize()
        }
        .disabled(!settings.enabled)
    }

    @ViewBuilder private var modelField: some View {
        TextField("Model", text: $settings.model, prompt: Text(modelPlaceholder))
            .disabled(!settings.enabled)
            .onChange(of: settings.model) { testResult = nil }
    }

    @ViewBuilder private var apiKeyField: some View {
        SecureField("\(settings.backend.displayName) API Key", text: apiKeyBinding, prompt: Text(keyPlaceholder))
            .disabled(!settings.enabled)
    }

    @ViewBuilder private var testConnection: some View {
        HStack {
            Button("Test Connection") { runTest() }
                .disabled(!settings.enabled || isTesting)
            if isTesting {
                ProgressView().controlSize(.small)
            }
            switch testResult {
            case let .success(model, milliseconds):
                Label("Reached \(model) in \(milliseconds) ms", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failure(let message):
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case nil:
                EmptyView()
            }
            Spacer()
        }
    }

    // MARK: - Bindings

    /// Switching provider swaps the key field to the new provider's Keychain entry and fills in the model and
    /// base URL when they are empty or still the previous provider's defaults.
    private var providerBinding: Binding<AIBackendKind> {
        Binding(
            get: { settings.backend },
            set: { newKind in
                let previous = settings.backend
                guard newKind != previous else { return }
                if settings.model.isEmpty || settings.model == previous.defaultModel {
                    settings.model = newKind.defaultModel
                }
                if newKind == .openAICompatible && settings.baseURL.isEmpty {
                    settings.baseURL = newKind.defaultBaseURL
                }
                settings.backend = newKind
                apiKey = keychain.get(AISettings.keychainKey(for: newKind)) ?? ""
                testResult = nil
            }
        )
    }

    /// Saves to the selected provider's Keychain entry on every user edit (and not when the provider switch
    /// replaces the text).
    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { apiKey },
            set: { newValue in
                apiKey = newValue
                testResult = nil
                let key = AISettings.keychainKey(for: settings.backend)
                if newValue.isEmpty {
                    keychain.delete(key)
                } else {
                    keychain.set(newValue, forKey: key)
                }
            }
        )
    }

    private var modelPlaceholder: String {
        settings.backend.defaultModel.isEmpty ? "Model name" : settings.backend.defaultModel
    }

    private var keyPlaceholder: String {
        settings.backend == .openAICompatible ? "Optional for local servers" : "Required"
    }

    // MARK: - Actions

    private func apply(_ preset: AIBackendPreset) {
        settings.baseURL = preset.baseURL
        if !preset.model.isEmpty { settings.model = preset.model }
        testResult = nil
    }

    private func runTest() {
        let snapshot = settings
        let key = apiKey
        isTesting = true
        testResult = nil
        Task {
            let result = await AICompletionConnectionTester().test(
                backend: snapshot.backend.backend,
                configuration: snapshot.configuration(apiKey: key)
            )
            isTesting = false
            testResult = result
        }
    }
}
