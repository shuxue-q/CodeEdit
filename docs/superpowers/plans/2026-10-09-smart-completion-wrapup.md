# Smart Completion — Wrap-up Plan (fixes and documentation after phases 1–3)

Spec: `docs/superpowers/specs/2026-10-09-smart-completion-engine-design.md`.
Phases 1–3 are on `main` (merge commits `7b247964`, `68d2309f`, `e79e768e`); their plans in
`docs/superpowers/plans/` describe what exists.
Branch: `fix/smart-completion-wrapup` (cut from `main`; never merged or pushed without the
user's instruction). The dominant intent is bug fixing, so the prefix is `fix/`.

These are the follow-ups the phase 2 and phase 3 sessions reported. Work through the steps in
order; each step ends with a green build, the new tests passing, `swiftlint --strict` clean on the
touched files (the six pre-existing violations in `FeatureIcon`, `OpenQuicklyListItemView`,
`PDFFileView`, `InspectorTab` and the package's `RainbowBracketTests` are known and not yours),
and one commit. Do not start the next step with a red build.

## Step 0 — Baseline

- Copy this plan into `docs/superpowers/plans/2026-10-09-smart-completion-wrapup.md`, read it,
  the spec and `CLAUDE.md`. Build with `-derivedDataPath /private/tmp/claude-501/DD`, run every
  suite under `CodeEditTests/Features/Completion` plus `LSPCompletionTests` for a green baseline.
  Commit the plan (`docs(completion): ...`).

## Step 1 — `return` slot works on half-typed code (`fix(completion): ...`)

Problem: `ExpectedTypeResolver.returnType(at:in:)` (`CodeEdit/Features/Completion/Semantics/
ExpectedTypeResolver.swift`, around line 99) needs a tree-sitter `function_definition` around the
cursor. While the user is typing `return pre|`, the tree often has no such node (the phase 3
session hit exactly this and added a text-scan fallback for the AI prompt in
`FunctionSignatureText.enclosing(in:before:)`). So the expected-type bonus for `return` is
usually missing in the real editor.

Fix: when the tree lookup yields nothing, fall back to `FunctionSignatureText.enclosing` and
parse the return type out of the header text: everything before the function name's
identifier, minus storage/qualifier words (`static`, `inline`, `virtual`, `constexpr`, `extern`,
`explicit`), keeping `*` / `&` depth the way the tree path does; `void` stays "no expected
type". Lambdas (`[...](...) {`) and headers that cannot be parsed return `nil`, never a wrong type.
Apply the same fallback to the `case` slot only if it also depends on the tree (check
`ExpectedTypeSlotScanner`); otherwise leave it.
Tests: `ExpectedTypeResolverTests` additions with a document whose tree is stale or absent
(use the test environment double the existing tests use), covering `int f() { return pre`,
`std::string *g() const { return `, `static void h() { return ` (nil), and a lambda body (nil).
Add one golden case for `return` under the no-tree condition.

## Step 2 — OpenAI backend parameters for current models (`fix(completion): ...`)

Problem: `OpenAIChatBackend.requestBody` (`CodeEdit/Features/Completion/AI/Backends/
OpenAIChatBackend.swift`, around line 58) always sends `max_tokens` and `temperature: 0.2`.
OpenAI's newer models reject `max_tokens` (they want `max_completion_tokens`) and some reject
any non-default `temperature`, so the default `.openAI` configuration can fail on every request.

Fix: the body depends on the backend kind the configuration carries:
- `.openAI`: send `max_completion_tokens: 256`, omit `temperature`.
- `.openAICompatible`: keep `max_tokens: 256` and `temperature: 0.2` (Ollama, LM Studio,
  DeepSeek and friends accept them).
Also, on an HTTP 400 whose error message names a parameter (`"Unsupported parameter"`,
`"unsupported_value"`, or the parameter name `temperature` / `max_tokens`), retry once with the
other variant of the body and remember the working variant for that configuration (a
per-configuration flag on the provider; cleared when the configuration changes).
Tests: `OpenAIChatBackendTests` for both bodies; `CloudAICompletionProviderTests` for the
one-time retry using the stubbed `URLProtocol`.

## Step 3 — Back off on a bad configuration (`fix(completion): ...`)

Problem: `CloudAICompletionProvider.backoffDuration(forStatus:)` returns `nil` for 400, 404 and
422, so a wrong model name or base URL resends a request on every keystroke.

Fix: 400 (after the step 2 retry), 404 and 422 back off for 2 minutes and log once with the
backend kind and the server's message; the existing rule that changing provider, model, base URL
or key clears the back-off already covers recovery. Test Connection must ignore the back-off
(it is the user's explicit action) and clear it on success.
Tests: `CloudAICompletionProviderTests` additions with the injected clock; a
`AICompletionConnectionTesterTests` case for "ignores and clears the back-off".

## Step 4 — User documentation (`docs(completion): ...`)

- New `docs/code-completion.md`, in English, in the style of `docs/cmake-project-presets.md`:
  what the popup offers (sources and badges), how ranking works at a high level (intent,
  expected type, frequency/recency/proximity), the behaviours added in phases 1–3 (automatic
  includes, call parentheses and parameter hints, commit characters, preselection, document
  words, postfix templates with the full table, chain completion on ⌃⇧Space, latency budget),
  the AI completion settings (providers, base URL presets, Keychain, Test Connection, what is
  sent and when), and where the local statistics and metrics files live. Check every claim
  against the current source before writing it.
- Update the completion paragraph in `CLAUDE.md` (around line 215) to name the new directories
  `Features/Completion/Semantics/`, `Features/Completion/AI/`, and the postfix / chain / word
  providers, in two or three sentences; do not restructure the file.
- Documentation-only commit: no code changes in this step.

## Verification before reporting

- Full build, `swiftlint --strict` at the repo root.
- All `CodeEditTests/Features/Completion` suites and `LSPCompletionTests` pass; the phase 1
  latency tests unchanged.
- Real clangd check (skip with a message if `/usr/bin/clangd` is unavailable): in the
  `ClangdCompletionIntegrationTests` style, `int f() { return ` with a stale tree now ranks an
  `int` variable above a `std::string` one.
- No live request to a cloud provider is expected; do not ask for or print any API key.
- Report each step as verified / not verified / blocked and list every deviation. Do not merge
  into `main`, do not push. Report back with the commit list.
