# Unified Completion Aggregator — Design

Date: 2026-09-28
Status: approved (user chose: Claude API opt-in AI provider; implementation by a Sonnet 5 subagent)

## Problem

`LSPCompletionDelegate` is the only `CodeSuggestionDelegate`. It is installed per document by
`CodeFileView` and serves only language-server items: no local snippets, no AI suggestions, no
ranking beyond the server's order, and prefix-only filtering. We want one pipeline that merges
several sources, then deduplicates, fuzzy-filters, ranks, and badges the result.

## Architecture

New app-side feature directory: `CodeEdit/Features/Completion/`.

```
TextViewController ──► CompletionAggregator : CodeSuggestionDelegate
                         │ 1. context   SyntacticContextResolver (tree-sitter nodes at cursor)
                         │ 2. fan-out   concurrent provider requests, per-provider deadline
                         │      ├─ LSPCompletionProvider      (logic moved out of LSPCompletionDelegate)
                         │      ├─ TreeSitterSnippetProvider  (context-gated snippets + plain keywords)
                         │      └─ AICompletionProvider       (protocol) ← ClaudeCompletionProvider (opt-in)
                         ▼ [CompletionCandidate]
                       CompletionPipeline (pure value types; unit-tested with no editor)
                         Deduplicator → FuzzyMatcher → CompletionRanker → CompletionPresenter
                         ▼ [AggregatedCompletionEntry : CodeSuggestionEntry]
                       CompletionFrequencyStore (accepted items → counts; persisted)
```

### Core types

- `CompletionSource`: `.lsp`, `.snippet`, `.keyword`, `.ai`. Determines the badge.
- `CompletionCandidate` (struct): `id`, `label`, `filterText`, `sortText?`, `score: Double?`
  (server-supplied relevance, if any), `kind: LSPCompletionCategory`, `source`, `detail?`,
  `documentation?`, `deprecated`, plus `payload: CompletionPayload`: an enum that holds what is
  needed to apply the item (`.lsp(CompletionItem)`, `.snippet(body: String)`,
  `.plain(insertText: String)`). Applying an item goes back to the owning provider, which keeps
  the existing LSP text-edit, `#include`, and snippet tab-stop behavior.
- `CompletionContext` (struct): `prefix`, `prefixRange`, `triggerCharacter?`, `syntax:
  SyntacticContext`, `languageId`, `documentText` window, and the cursor offset.
- `SyntacticContext`: `.memberAccess` (after `.`, `->`, `::`), `.preprocessor`, `.comment`,
  `.string`, `.typePosition`, `.statement` (inside a function body), `.topLevel`, `.unknown`.
  Resolved from `TreeSitterClient.nodesAt(location:)`, which walks node types such as
  `comment`, `string_literal`, `preproc_*`, `field_expression`, `compound_statement`, and
  `translation_unit`, with text fallbacks when there is no tree.

### Provider protocol

```swift
@MainActor protocol CompletionProvider: AnyObject {
    var source: CompletionSource { get }            // primary source for badging
    var deadline: Duration { get }                  // .zero = always awaited (LSP, snippets); AI 2.5s
    func triggerCharacters() -> Set<String>
    func candidates(for context: CompletionContext, textView: TextViewController) async -> [CompletionCandidate]
    func apply(_ candidate: CompletionCandidate, textView: TextViewController, cursorPosition: CursorPosition?)
    func resolve(_ candidate: CompletionCandidate) async -> CompletionCandidate?   // default nil
}
```

The aggregator queries all providers concurrently. Zero-deadline providers (LSP, snippets) are
awaited in full, as LSP was before. The menu opens as soon as they return; the AI provider is only
waited on (up to its deadline) when they returned nothing. An AI result that arrives after its deadline is stored and merged in on
the next `completionOnCursorMove`, provided the request offset still matches. A slow network call
therefore never blocks the menu.

### Pipeline stages

1. **Deduplication.** Group by the normalized label (trimmed; clangd's `•` and leading space
   removed; case-sensitive). When a group contains a `.snippet`-kind candidate from any source,
   drop the `.keyword`/`.plain` candidates in that group. When there are exact duplicates across
   sources (same label and kind), keep the one ranked highest by source priority
   (`lsp > snippet > keyword > ai`), and record the sources it merged with so the merged sources
   can still be shown.
2. **Fuzzy filtering.** `FuzzyMatcher.match(pattern:candidate:) -> FuzzyMatch?` runs against
   `filterText` (falling back to `label`). It does a case-insensitive subsequence match and
   returns the score and the matched indices. Bonuses: exact-case match, a match at index 0, a
   match at a word boundary (`_`, a camelCase hump, or after a non-alphanumeric), and consecutive
   runs. Penalties: gaps and leading unmatched characters. A leading `#` on the prefix is handled
   the same way as today. An empty prefix matches everything with score 0.
3. **Composite ranking.** `CompletionRanker` computes
   `score = wFuzzy·fuzzy + wServer·serverRank + wContext·contextWeight(kind, source, syntax) + wFreq·log1p(freq)`.
   `serverRank` normalizes the server's ordering: sort by `sortText` (falling back to the
   original index), map the position to a value in 1…0, and blend in `score` when it's present.
   The context weight table: `.memberAccess` boosts variables and functions and zeroes out
   snippets and keywords (they're removed entirely there); `.statement` boosts snippets and
   keywords; `.topLevel` boosts types and snippets such as `struct`/`class`; `.preprocessor`
   keeps only macros, files, and include snippets; in `.comment`/`.string` the aggregator
   returns nil unless the request was explicit. The weights live in a `RankingWeights` struct
   (defaults below) so tests can pin them. Ties are broken by label length, then
   alphabetically. AI candidates get a fixed rank band: at most `aiMaxItems` (3), placed after
   the top `aiInsertAfter` (2) non-AI items, so they never bury exact matches.
4. **Presentation and badging.** `CompletionPresenter` maps each candidate to an
   `AggregatedCompletionEntry`. The leading kind icon stays as it is today (it reuses the
   `LSPCompletionEntry` category icons and colors). A new trailing badge identifies the source:

   | Source   | Glyph (SF Symbol)                            | Tint      | A11y label       |
   |----------|----------------------------------------------|-----------|------------------|
   | lsp      | none (the default source shows no badge)     | —         | —                |
   | snippet  | `curlybraces`                                | `.teal`   | "Snippet"        |
   | keyword  | `textformat.abc`                             | `.pink`   | "Keyword"        |
   | ai       | `sparkles`                                   | `.purple` | "AI suggestion"  |

### Package change (CodeEditSourceEditor)

- Add `public struct CodeSuggestionBadge: Equatable { image: Image; color: Color; accessibilityLabel: String }`
  in `CodeSuggestion/Model/`.
- Add `var badge: CodeSuggestionBadge? { get }` to `CodeSuggestionEntry`, with a
  `public extension` default of `nil`. Existing conformers compile unchanged.
- `CodeSuggestionLabelView` draws the badge as the last element of the row, at the far right,
  after the trailing detail and the deprecation triangle. It uses a fixed-width column so labels
  line up, and white when `isSelected` with the accent layout.

```
┌──────────────────────────────────────────────────┐
│ ƒ  printf        int (const char *, ...)         │  ← LSP (no badge)
│ ⟨⟩ for           for (init; cond; inc) {…}   {}  │  ← snippet badge
│ 🔑 float                                    abc  │  ← keyword badge
│ ⟨⟩ for (int i = 0; i < n; ++i)               ✦  │  ← AI badge
└──────────────────────────────────────────────────┘
```

### TreeSitterSnippetProvider

- The snippet and keyword tables are keyed by language id (C, C++ in the first pass; the
  structure allows more). Each snippet has `label`, `body` (LSP snippet syntax: `${1:cond}`,
  `$0`), `detail`, and `allowedContexts: Set<SyntacticContext>`.
- Keywords are plain `.keyword` candidates (for example `for`, `while`, `if`, `return`,
  `struct`, `class`, `const`, `static`). Several of them overlap a snippet label on purpose,
  and the dedup stage suppresses those.
- Snippet bodies are applied through the same snippet parsing that exists today (move
  `parseSnippet`/`stripSnippetSyntax` into a shared `SnippetText` helper).

### AI provider (Claude API, opt-in)

- `AICompletionProvider` protocol (the `CompletionProvider` protocol with `source == .ai`) and
  `ClaudeCompletionProvider`.
- Raw HTTP through `URLSession`; Swift has no official Anthropic SDK. The request is
  `POST https://api.anthropic.com/v1/messages` with headers `x-api-key`,
  `anthropic-version: 2023-06-01`, `content-type: application/json`, and
  `anthropic-beta: server-side-fallback-2026-07-01`.
- Body: `model` (from settings, default `claude-opus-5`), `max_tokens: 1024`,
  `output_config: {effort: "low", format: {type: "json_schema", schema: …}}`,
  `fallbacks: "default"`, a fixed system prompt (put first so it can be cached), and a user
  message with the language, the file name, up to ~4,000 characters before the cursor and
  ~1,000 after, with a `<cursor/>` marker. The schema is
  `{completions: [{label, insertText}]}`, with at most 3 items.
- Branch on `stop_reason` before reading `content`. A `refusal` or a non-`end_turn` stop returns
  `[]`. HTTP and network errors return `[]` and log once, rate-limited; they never surface
  as UI errors.
- Debounce: the provider is skipped when the prefix is shorter than 2 characters and the request
  wasn't explicit, and a new request cancels the in-flight task.
- Settings: `Settings[\.textEditing].aiCompletion` with `enabled: Bool = false` and
  `model: String = "claude-opus-5"`, decoded with `decodeIfPresent ?? default`. The API key is
  stored in Keychain through `CodeEditKeychain` (key `anthropicAPIKey`), never in settings.json.
  UI: a new "AI Completions" section on the Text Editing settings page with a toggle, a model
  text field, a `SecureField` for the key, and a note that surrounding code is sent to
  Anthropic when enabled.

### Frequency table

`CompletionFrequencyStore` keeps a per-language `[normalizedLabel: count]` map with decay
(counts are multiplied by 0.95 on each save when they exceed 1,000 total, which keeps it
bounded). It's persisted as JSON at `~/Library/Application Support/CodeEdit/completion-frequency.json`,
with saves throttled the same way `Settings` autosave is. The store is injected so tests can use
an in-memory instance. It's incremented in `completionWindowApplyCompletion`.

## Wiring

- `CodeFileView` installs `CompletionAggregator(document:treeSitterClient:)` where it
  installs `LSPCompletionDelegate` today. `LSPCompletionDelegate` is refactored into
  `LSPCompletionProvider` (same file history: rename the type, keep the helpers), and a
  `typealias` isn't needed. Existing LSP completion tests move to the new type.
- `completionTriggerCharacters()` is the union of all the providers' trigger characters.
- `completionWindowResolve` forwards to the owning provider, which is how the LSP
  `completionItem/resolve` is reached today (check `LanguageServer+Completion.swift`; if resolve
  isn't implemented there, keep it returning nil).

## Non-goals

- Ghost-text or inline AI completion (the AI items show up only as menu rows).
- Snippet tab-stop navigation beyond the first stop. It keeps today's behavior.
- Languages other than C/C++ for snippet tables in this pass.

## Verification

- Unit tests (Swift Testing, `CodeEditTests/Features/Completion/`): dedup rules, fuzzy
  scoring order (`pf` → `printf` over `fprintf`; camelCase humps; `#inc`), ranker
  (sortText order preserved when the other signals are equal, frequency lifts, member-access
  context suppresses keywords, AI band placement), presenter badges, frequency-store round
  trip/decay, Claude request encoding and response/refusal decoding (URLProtocol stub, no
  network), and the syntactic context resolver on small C/C++ sources.
- Package test: `CodeSuggestionEntry` default badge is nil; the label view renders with a badge.
- Existing `LSPCompletionTests` / `LSPCompletionOriginTests` still pass.
- `swiftlint --strict` at the root and in `CodeEditSourceEditor/`.
- App check (per AGENTS.md): type `point.` in a C++ file with clangd and confirm that only
  member items appear. Type `fo` in a function body and confirm the `for` snippet appears with
  the `{}` badge and no duplicate `for` keyword row. Accept it and confirm the snippet expands.
