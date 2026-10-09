//
//  AICompletionSettings.swift
//  CodeEdit
//
//  Created by CodeEdit Contributors on 9/28/26.
//

import Foundation

extension AIBackendKind {
    /// The name shown in the settings provider picker.
    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openAI: return "OpenAI"
        case .openAICompatible: return "OpenAI-compatible"
        }
    }

    /// The model used when none is configured for this backend. Empty when the backend has no sensible default.
    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-opus-5"
        case .openAI: return "gpt-5"
        case .openAICompatible: return ""
        }
    }

    /// The base URL used when none is configured. Empty when the backend's own endpoint is used.
    var defaultBaseURL: String {
        switch self {
        case .anthropic, .openAI: return ""
        case .openAICompatible: return "http://localhost:11434/v1"
        }
    }

    /// The Keychain entry this backend's API key is stored under. One entry per backend, so switching
    /// providers never sends one vendor's key to another.
    var keychainKey: String {
        switch self {
        case .anthropic: return "anthropicAPIKey"
        case .openAI: return "openAIAPIKey"
        case .openAICompatible: return "openAICompatibleAPIKey"
        }
    }
}

/// A ready-made server entry for the OpenAI-compatible provider.
struct AIBackendPreset: Hashable, Identifiable {
    /// The server's name.
    let name: String
    /// The base URL to fill in.
    let baseURL: String
    /// A model to suggest; empty when it depends on what the user has installed.
    let model: String

    var id: String { name }
}

extension SettingsData.TextEditingSettings {
    /// Settings for the opt-in AI completion source.
    ///
    /// API keys are never persisted here; each backend has its own Keychain entry, see
    /// ``AICompletionSettings/keychainKey(for:)``, read by `CloudAICompletionProvider`.
    struct AICompletionSettings: Codable, Hashable {
        /// Servers that speak the OpenAI API, offered as starting points for the OpenAI-compatible
        /// provider. A read-only table; it is not stored in the settings file.
        static let presets: [AIBackendPreset] = [
            AIBackendPreset(name: "Ollama", baseURL: "http://localhost:11434/v1", model: ""),
            AIBackendPreset(name: "LM Studio", baseURL: "http://localhost:1234/v1", model: ""),
            AIBackendPreset(name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat"),
            AIBackendPreset(name: "Moonshot", baseURL: "https://api.moonshot.cn/v1", model: "kimi-k2-0905-preview"),
            AIBackendPreset(
                name: "Qwen (DashScope)",
                baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                model: "qwen3-coder-plus"
            )
        ]

        /// The Keychain key the API key of `backend` is stored under.
        static func keychainKey(for backend: AIBackendKind) -> String {
            backend.keychainKey
        }

        /// Whether the AI completion source is enabled. Off by default: surrounding code is
        /// only sent to the selected provider once the user opts in.
        var enabled: Bool = false
        /// The provider that serves AI completions.
        var backend: AIBackendKind = .anthropic
        /// The model used for completions.
        var model: String = AIBackendKind.anthropic.defaultModel
        /// The server's base URL. Only used by the OpenAI-compatible provider.
        var baseURL: String = ""

        /// Default initializer.
        init() {}

        /// Explicit decoder init for setting default values when a key is not present in `JSON`.
        ///
        /// A settings file written before providers existed has no `backend`; it decodes to Anthropic and
        /// keeps its `model`. An unknown provider name also falls back to Anthropic rather than failing the
        /// whole settings decode.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            let backend = (try? container.decodeIfPresent(AIBackendKind.self, forKey: .backend)) ?? .anthropic
            self.backend = backend
            self.model = try container.decodeIfPresent(String.self, forKey: .model) ?? backend.defaultModel
            self.baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? backend.defaultBaseURL
        }

        /// The backend configuration for the selected provider, with `apiKey` filled in.
        ///
        /// Only the OpenAI-compatible provider uses ``baseURL``; the others talk to their vendor's endpoint.
        func configuration(apiKey: String) -> AIBackendConfiguration {
            var url: URL?
            if backend == .openAICompatible {
                url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return AIBackendConfiguration(
                model: model.trimmingCharacters(in: .whitespacesAndNewlines),
                baseURL: url,
                apiKey: apiKey
            )
        }
    }
}
