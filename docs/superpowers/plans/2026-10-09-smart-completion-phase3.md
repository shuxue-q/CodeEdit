# Smart Completion — Phase 3 Implementation Plan (pluggable AI backends)

Spec: `docs/superpowers/specs/2026-10-09-smart-completion-engine-design.md`, section "Phase 3".
Phase 1 and 2 are on `main` (merge commits `7b247964` and `68d2309f`); their plans in
`docs/superpowers/plans/` describe what exists.
Branch: `feat/smart-completion-phase3` (cut from `main`; never merged or pushed without the
user's instruction).

User decision: AI completion keeps using cloud APIs, but the provider must be able to target
other vendors' APIs, not only Anthropic. AI remains an opt-in, secondary source: it keeps its
deadline, late-merge and fixed-band placement from phase 1, and nothing in this phase may slow
the popup for users who leave AI off.

Work through the steps in order. Each step ends with: build passes, the new tests pass,
`swiftlint --strict` is clean for the touched files (pre-existing violations in `FeatureIcon`,
`OpenQuicklyListItemView`, `PDFFileView`, `InspectorTab`, `RainbowBracketTests` are known and
not yours), and one commit on the branch with a `feat(completion): ...` message. Do not start the
next step with a red build.

## Step 0 — Baseline

- Copy this plan into `docs/superpowers/plans/2026-10-09-smart-completion-phase3.md` in the
  worktree, read the spec and the phase 1 / phase 2 plans, read `CLAUDE.md`.
- Build (`-derivedDataPath /private/tmp/claude-501/DD`) and run every suite under
  `CodeEditTests/Features/Completion` plus `LSPCompletionTests` to confirm a green baseline.
  Commit the plan.

## Step 1 — Backend abstraction (no behaviour change)

New: `CodeEdit/Features/Completion/AI/AICompletionBackend.swift` (protocol),
`.../AI/AICompletionRequest.swift`, `.../AI/AICompletionPrompt.swift` (the shared system prompt,
context splitting and intent description moved out of `ClaudeCompletionProvider`),
`.../AI/Backends/AnthropicMessagesBackend.swift` (the existing request body, headers, and
structured-output parsing moved verbatim).
Changed: `ClaudeCompletionProvider.swift` becomes `CloudAICompletionProvider.swift`
(`final class CloudAICompletionProvider: AICompletionProvider`) that owns cancellation, the
deadline, the minimum prefix rule, error-log throttling, and delegates the network call to a
backend chosen by the settings. Keep a `typealias ClaudeCompletionProvider = CloudAICompletionProvider`
only if it avoids touching unrelated call sites; otherwise rename the references
(`CompletionAggregator.swift` line ~90, tests).

```swift
struct AICompletionRequest: Sendable {
    let before: String          // text before the cursor, already truncated
    let after: String           // text after the cursor, already truncated
    let prefix: String          // the word being typed
    let languageId: String
    let intentDescription: String
    let expectedType: String?   // from phase 2, when known
    let maxSuggestions: Int
}

protocol AICompletionBackend: Sendable {
    var kind: AIBackendKind { get }
    func makeRequest(_ request: AICompletionRequest, configuration: AIBackendConfiguration) throws -> URLRequest
    func suggestions(from data: Data, response: HTTPURLResponse) throws -> [String]
}
```

`AIBackendConfiguration` carries `model`, `baseURL`, `apiKey`, and `extraHeaders`.
Tests: move `ClaudeCompletionProviderTests` into `CloudAICompletionProviderTests` +
`AnthropicMessagesBackendTests`; every existing assertion must still pass unchanged.

## Step 2 — OpenAI-compatible backend

New: `.../AI/Backends/OpenAIChatBackend.swift`: `POST {baseURL}/chat/completions` with
`Authorization: Bearer`, `model`, `messages` (system prompt + user prompt with the
`<cursor/>` marker), `temperature: 0.2`, `max_tokens: 256`, `n: 1`, and a JSON response
format request (`response_format: {type: "json_object"}`) asking for
`{"completions": ["...", "..."]}`; fall back to parsing a fenced or bare JSON array, and to
splitting the content on newlines when the model ignores the format. Handle `choices[0].message.content`
and the streaming-less error envelope (`error.message`). The same backend serves OpenAI,
DeepSeek, Moonshot, Qwen (DashScope compatible mode), Ollama (`http://localhost:11434/v1`), LM Studio
and any other OpenAI-compatible server, differing only by `baseURL`, `model`, and whether an
API key is required (allow an empty key when the host is loopback).
Tests: `OpenAIChatBackendTests.swift`: request shape (URL, headers, body), parsing of the
three response shapes, error envelope, loopback-without-key.

## Step 3 — Settings model and migration

Changed: `AICompletionSettings.swift`:

```swift
enum AIBackendKind: String, Codable, CaseIterable { case anthropic, openAI, openAICompatible }
var enabled: Bool = false
var backend: AIBackendKind = .anthropic
var model: String = "claude-opus-5"                  // default depends on backend; see below
var baseURL: String = ""                             // only used by .openAICompatible
var presets: [AIBackendPreset]                       // read-only table, not persisted
```

Per-backend defaults: anthropic → `claude-opus-5`, openAI → `gpt-5`, openAICompatible → empty
model + `http://localhost:11434/v1`. Keep the `init(from:)` `decodeIfPresent ?? default` pattern:
an old settings file without `backend` must decode to `.anthropic` with its old `model`.
Keychain: one key per backend (`anthropicAPIKey` unchanged, `openAIAPIKey`,
`openAICompatibleAPIKey`); `AICompletionSettings.keychainKey(for:)` replaces the static
constant. Nothing is persisted in `settings.json` besides the fields above.
Tests: `AICompletionSettingsTests.swift` (decode old file, decode each backend, defaults).

## Step 4 — Settings UI

Changed: `TextEditingSettingsView+Completion.swift` (and `TextEditingSettingsView.swift` where
it loads the key). Layout, following the existing rows:

```
AI Completion                                  [toggle]
  Provider        [Anthropic ▾ | OpenAI | OpenAI-compatible]
  Base URL        [http://localhost:11434/v1          ]   (only for OpenAI-compatible)
  Model           [claude-opus-5                       ]
  API Key         [••••••••••••••••••••••]  (per provider; saved to Keychain on change)
  [Test Connection]   ✓ Reached gpt-5 in 480 ms / ✗ 401 Unauthorized
  Note: code around the cursor is sent to the selected provider only while this is on.
```

"Test Connection" sends a minimal request through the chosen backend (bounded 5 s) and shows
the outcome inline; it never writes anything to the editor. Switching provider swaps the key
field to that provider's Keychain entry and resets the model field to the backend default when
it is empty. Use the existing `SettingsForm` / `Section` conventions in that file; no Liquid
Glass APIs.
Verification: open Settings → Text Editing in the running app (`open
/private/tmp/claude-501/DD/Build/Products/Debug/CodeEdit.app`), take a screenshot of the
section with each provider selected, and attach the screenshots' paths to the report.

## Step 5 — Richer prompt context

Changed: `AICompletionPrompt.swift`, `CompletionAggregator+Gathering.swift` (pass what phase 2
already resolved), `CloudAICompletionProvider.swift`.

- Include the phase 2 expected type and receiver type in the user prompt when known
  ("The expression should produce a `std::string`.").
- Include the enclosing function's signature line (from the tree-sitter `function_definition`
  the phase 2 return-type resolver already locates) so the model sees parameter names even
  when the 4 000-character window cuts the function head.
- Include up to 3 `#include`d project headers' public declarations? No: too slow and too
  large. Leave a TODO comment and skip.
- Keep the token budget: before-cursor window stays 4 000 characters, after-cursor 1 000,
  extra context at most 600 characters.
Tests: `AICompletionPromptTests.swift` (prompt contains the extra lines only when known; size caps).

## Step 6 — Robustness

Changed: `CloudAICompletionProvider.swift`.

- HTTP 429 / 529 / 5xx: back off for 30 s (no requests, no log spam), then retry on the next
  trigger; 401 / 403: back off for 5 min and log once with the backend name.
- Network unreachable: back off 60 s.
- Responses that are not valid for the backend never surface as candidates; a suggestion that
  duplicates an existing non-AI candidate label is dropped by the existing deduplicator.
- Record backend latency into `CompletionMetricsStore` under the provider name.
Tests: `CloudAICompletionProviderTests.swift` additions with a stubbed `URLProtocol`.

## Verification before reporting

- Full build, `swiftlint --strict` at the repo root.
- All `CodeEditTests/Features/Completion` suites and `LSPCompletionTests` pass; the phase 1
  latency tests unchanged.
- Settings screenshots for the three providers.
- With a real key for at least one backend if the user provides one in the session (do not ask
  for the user's keys in chat; if none is configured, say the live request is not verified):
  type in a C++ file with AI on and confirm the AI band appears after the top items.
- Report each step as verified / not verified / blocked and list every deviation.
- Do not merge into `main`, do not push. Report back with the commit list.
