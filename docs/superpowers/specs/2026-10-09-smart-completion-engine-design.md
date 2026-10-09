# Smart Completion Engine — Design

Date: 2026-10-09
Status: approved (user decisions recorded below)
Supersedes nothing; builds on `2026-09-28-completion-aggregator-design.md` and
`2026-09-28-completion-aggregator.md` (the plan), which describe the pipeline this
document extends.

## Goal

Bring CodeEdit's code completion to the level of Visual Studio and CLion for C and C++:
the popup proposes the right item first, accepting an item does the follow-up work
(headers, parentheses, parameter hints), and the window never stalls the editor.

## Decisions (from the design Q&A)

| Question | Decision |
| --- | --- |
| Language focus | C / C++ with clangd first. Other languages keep working through LSP but get no new heuristics in phases 1–2. |
| Meaning of "smart" | Ranking and context accuracy (CLion-style), not AI text generation. AI stays an opt-in provider. |
| AI backend | Cloud APIs stay allowed; the AI provider must be able to target other vendors' APIs (phase 3). |
| Phase 1 features | All of them, implemented in the importance order given below. |
| Latency budget | The popup must open or update within 500 ms, never later than 1 s after the keystroke. |
| Vendored editor | Changes to `CodeEditSourceEditor` (popup, key handling) are allowed. |
| Implementation | Delegated to a Sonnet 5.5 agent session, one phase per session. |

## Current pipeline (unchanged shape)

```
keystroke / trigger character
  └► CompletionAggregator (CodeEdit/Features/Completion/CompletionAggregator.swift)
       ├ 1. CompletionIntentRecognizer → CompletionIntent   (tree-sitter + C-family token rules)
       ├ 2. providers, concurrent, each with a deadline
       │     LSPCompletionProvider · TreeSitterSnippetProvider · ClaudeCompletionProvider
       ├ 3. CompletionDeduplicator → FuzzyMatcher → CompletionRanker (+ CompletionFrequencyStore)
       └ 4. CompletionPresenter → AggregatedCompletionEntry → SuggestionController (vendored popup)
```

The weights live in `RankingWeights`; the intent weights in `CompletionIntentPolicy`.

## Gap analysis against VS / CLion

Ordered by how much the user notices it. This order is the implementation order.

1. Accepting an item does not apply `additionalTextEdits` (clangd's automatic `#include`).
2. Accepting a function does not insert `()` or open parameter hints.
3. No commit characters: typing `(` or `.` while the popup is open does not accept the item.
4. No "best match" preselection; the first row is always selected.
5. No fallback when the language server is absent or slow: no document-word completion.
6. Ranking knows syntax (intent) but not history beyond a global per-label count: no recency,
   no "this symbol is used in this file", no per-intent statistics.
7. A slow server blocks the window; the latency budget is not enforced.
8. (Phase 2) Ranking does not know the expected type; no postfix completion; no chain completion.
9. (Phase 3) The AI provider is Anthropic-only.

## Phase 1 — popup behaviour parity with VS (this phase is implemented first)

### 1.1 Automatic includes: `additionalTextEdits`

- `LSPCompletionProvider.apply` applies the item's `additionalTextEdits` in addition to the
  primary edit. Edits are applied in descending document order so earlier offsets stay valid;
  the primary edit is one entry in that sorted list.
- If the accepted item has not been resolved yet and the server advertises
  `completionProvider.resolveProvider`, resolve it first (bounded by a 300 ms timeout; on
  timeout apply without the extra edits). clangd returns `additionalTextEdits` on the initial
  item when `--header-insertion` is on, so resolution is rarely needed.
- The gutter/undo grouping: the whole acceptance is one undo group.
- Setting: `textEditing.completion.applyAdditionalEdits` (default `true`).

### 1.2 Function call completion

- When the accepted candidate's kind is `.function` (method, function, constructor) and the
  inserted text is plain (not an LSP snippet), and the character after the cursor is not `(`:
  insert `()` and place the caret between the parentheses when the signature has parameters,
  after them when it does not. The signature comes from `detail` / `labelDetails`; when it
  cannot be parsed, place the caret between the parentheses.
- Items that already arrive as snippets (`insertTextFormat == .snippet`, clangd's
  `--function-arg-placeholders`) are inserted as they are.
- After insertion, request signature help through the existing
  `LSPSignatureHelpCoordinator` (the coordinator already reacts to the `(` trigger; the
  provider only has to make sure the text change goes through the same path).
- Setting: `textEditing.completion.insertParenthesesForFunctions` (default `true`).

### 1.3 Commit characters

- New delegate hook in the vendored package:
  `CodeSuggestionDelegate.completionCommitCharacters(for item: CodeSuggestionEntry) -> Set<Character>`.
  `SuggestionViewController`'s key handling accepts the selected row when a commit
  character is typed, then inserts the character (so `foo(` yields `foo(` with the caret inside).
- The aggregator returns the LSP item's `commitCharacters` when present, otherwise a per-language
  default. C family default: `( . ; , ) [ >` with `>` only meaningful after `-`.
- Commit only when the typed prefix is non-empty and the selected item is a fuzzy match of it.
  Never commit on an empty prefix (`obj.` then `(` must not accept the first member).
- Setting: `textEditing.completion.commitCharactersEnabled` (default `true`).

### 1.4 Best-match preselection

- `CompletionRanker` returns `RankedCompletions { items: [CompletionCandidate], preselectedIndex: Int }`.
  The preselected row is the top item when: the LSP item has `preselect == true`, or the top
  score beats the second by `RankingWeights.preselectMargin` (default 1.5), or the top item's
  label starts with the typed prefix case-sensitively and the second does not.
- `CodeSuggestionDelegate.completionSuggestionsRequested` and `completionOnCursorMove` return
  the preselected index alongside the items (new associated value, default 0 for other delegates).
- `SuggestionViewController` selects that row and renders its label in bold.

### 1.5 Document word provider

- `DocumentWordProvider: CompletionProvider` with `source: .word` (new `CompletionSource` case,
  badge "Word"). It yields identifiers from the current document, excluding the word at the
  cursor and anything shorter than 3 characters. Tokenization runs off the main actor on a
  snapshot of the text and is cached per document content version.
- Kind `.text`, offered only when the prefix has at least 2 characters or the request is explicit,
  and only for intents `.expression`, `.statement`, `.unknown`, `.topLevel`, `.typeName`.
- Dedup already collapses a word against an LSP item with the same label; the word is dropped.
- `CompletionIntentPolicy.weight` returns 0.25 for `.word` candidates in the allowed intents.

### 1.6 Ranking signals

- Frequency store key becomes `(languageId, intent, label)`; the old per-language table stays as
  a fallback with half weight so existing data keeps helping.
- Recency: the store records the last acceptance time per key; the ranker adds
  `weights.recency * exp(-age / 30 min)` (default `recency = 0.4`).
- Proximity: the `DocumentWordProvider`'s identifier set is also passed into `CompletionContext`
  as `documentIdentifiers: Set<String>`; a candidate whose label is in the set gets
  `weights.proximity` (default 0.5). This is what makes "symbols used in this file" float up.
- Exact-case prefix match keeps its existing fuzzy bonus; no change.

### 1.7 Latency guard

- `LSPCompletionProvider.deadline` becomes `.milliseconds(800)` instead of `.zero`. The
  aggregator's late-merge path (today only used for AI) applies to any provider: when the LSP
  answer arrives after the window opened with local candidates, the next cursor move merges it.
  When no local candidate exists the aggregator waits for the LSP up to the deadline, then
  shows nothing and merges on the next keystroke.
- `TreeSitterSnippetProvider` and `DocumentWordProvider` stay at `.zero` (they are synchronous
  or cached).
- Instrumentation: `CompletionMetricsStore` (local only, `~/Library/Application Support/CodeEdit/
  completion-metrics.json`) records per session: popup count, accept count, rank of the accepted
  item, keystrokes between popup and accept, and provider latencies (p50/p95). No network.

## Phase 2 — CLion-style semantic ranking (separate session after phase 1 is merged)

- Expected-type inference: tree-sitter gives the slot (assignment RHS, `return`, argument
  position); LSP signature help / hover gives the type of the slot; candidates whose `detail`
  type matches get a strong bonus. Also use clangd's `score` field fully.
- Postfix completion provider for C/C++: `.if`, `.else`, `.not`, `.for`, `.fori`, `.forr`,
  `.return`, `.var`, `.new`, `.par`, `.cast` operating on the expression node before the cursor.
- Context-keyed statistics: key `(intent, receiver type, label)` for member access.
- Chain completion (explicit key binding): members reachable in two hops that match the
  expected type.

## Phase 3 — AI backends

- `AICompletionBackend` protocol with `AnthropicMessagesBackend`, `OpenAIChatBackend`
  (OpenAI-compatible endpoints, custom base URL), selected in settings. `ClaudeCompletionProvider`
  becomes `AICompletionProvider` over a backend. Keychain key per backend.

## Measurement and tests

- Golden cases: `CodeEditTests/Features/Completion/Golden/*.swift` hold `(source, cursor,
  candidates, expected top 3, expected preselection)` fixtures run through
  `CompletionRanker` and `CompletionIntentRecognizer` without an editor.
- Each phase 1 feature gets unit tests next to the existing ones in
  `CodeEditTests/Features/Completion/`. Vendored popup changes get tests in
  `CodeEditSourceEditor/Tests/CodeEditSourceEditorTests/`.
- Manual verification per feature in the running app with a C++ file and clangd: `std::vec`
  → accept → `#include <vector>` appears; `obj.` → `(` commits; `fo` preselects `foo` when it
  is the only strong match.
