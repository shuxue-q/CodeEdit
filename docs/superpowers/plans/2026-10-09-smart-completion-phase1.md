# Smart Completion — Phase 1 Implementation Plan

Spec: `docs/superpowers/specs/2026-10-09-smart-completion-engine-design.md`
Branch: `feat/smart-completion-phase1` (cut from `main`; never merged or pushed without the
user's instruction).

Work through the steps in order. Each step ends with: build passes, the new tests pass,
`swiftlint --strict` is clean for the touched files, and one commit on the branch. Do not start
the next step with a red build.

## Step 0 — Baseline

- Copy the spec and this plan into the branch (they are untracked in the main checkout).
- Build the app and run the existing completion tests:
  `-only-testing:CodeEditTests/CompletionAggregatorTests`, `CompletionRankerTests`,
  `CompletionIntentPolicyTests`, `CompletionIntentRecognizerTests`, `FuzzyMatcherTests`,
  `CompletionDeduplicatorTests`, `CompletionFrequencyStoreTests`, `CompletionPresenterTests`,
  `TreeSitterSnippetProviderTests`, `ClaudeCompletionProviderTests`, `LSPCompletionTests`.
- Commit the docs.

## Step 1 — `additionalTextEdits` (spec 1.1)

Files: `CodeEdit/Features/Completion/Providers/LSPCompletionProvider.swift`,
`CodeEdit/Features/Settings/Pages/TextEditingSettings/Models/TextEditingSettings.swift` (+ view),
tests in `CodeEditTests/Features/LSP/LSPCompletionTests.swift`.

- Collect primary edit + `additionalTextEdits`, sort by range descending, apply inside one
  undo group (`textView.textView.undoManager?.beginUndoGrouping()`).
- Resolve-before-apply with a 300 ms timeout when `additionalTextEdits` is nil and the server
  supports resolve.
- Tests: edits applied in the right order; include inserted above the cursor leaves the caret on
  the completed symbol; setting off skips the extra edits.

## Step 2 — Function call completion (spec 1.2)

Files: `LSPCompletionProvider.swift`, new `CodeEdit/Features/Completion/Pipeline/FunctionCallInsertion.swift`
(pure: given label/detail/next character, returns text to insert and caret offset), settings,
tests `FunctionCallInsertionTests.swift`.

- Only for plain-text items of kind `.function`; never for snippet items; never when the next
  character is `(`.
- After insertion, make sure `LSPSignatureHelpCoordinator` sees the `(` (it listens to text
  changes through `textViewDidChangeText`; verify in the app that the hint appears).

## Step 3 — Commit characters (spec 1.3)

Files (vendored package): `CodeEditSourceEditor/Sources/CodeEditSourceEditor/CodeSuggestion/Model/CodeSuggestionDelegate.swift`,
`.../TableView/SuggestionViewController.swift` (key handling around line 169–210),
`.../Model/SuggestionViewModel.swift`.
Files (app): `CompletionAggregator.swift`, new `CodeEdit/Features/Completion/Models/CommitCharacters.swift`.

- Delegate hook with a default implementation returning `[]` so other delegates keep compiling
  (`JumpToDefinitionModel`, example app's `MockCompletionDelegate`).
- Commit only with a non-empty prefix that fuzzy-matches the selected item.
- Tests: package test for the key path (`SuggestionCompletionTests.swift` already exercises
  acceptance), app test for the character set and the empty-prefix guard.

## Step 4 — Best-match preselection (spec 1.4)

Files: `CompletionRanker.swift`, `RankingWeights.swift`, `CompletionAggregator.swift`,
`CodeSuggestionDelegate.swift` (return type gains `preselectedIndex`), `SuggestionViewModel.swift`,
`SuggestionViewController+Layout.swift` (row selection, currently hard-coded to 0 at line 153),
`CodeSuggestionLabelView.swift` (bold label).

- Keep the old delegate signature working via a default-argument overload so the vendored
  example app and tests compile.
- Tests: ranker preselection rules (LSP `preselect`, margin, exact prefix); view model selects
  the given row.

## Step 5 — Document word provider (spec 1.5)

Files: new `CodeEdit/Features/Completion/Providers/DocumentWordProvider.swift`,
`CompletionSource.swift` (`.word` + badge), `CompletionIntentPolicy.swift`, `CompletionAggregator.swift`
(register the provider), `CodeEditSourceEditor/.../CodeSuggestionBadge.swift` if a new badge
style is needed, tests `DocumentWordProviderTests.swift`.

- Off-main-actor tokenizer over a `String` snapshot; cache keyed by document content hash or
  change count; cap at 5 000 identifiers.

## Step 6 — Ranking signals (spec 1.6)

Files: `CompletionFrequencyStore.swift` (new keyed schema, migration from the old file format),
`CompletionRanker.swift`, `RankingWeights.swift`, `CompletionContext.swift`
(`documentIdentifiers`), tests `CompletionRankerTests.swift`, `CompletionFrequencyStoreTests.swift`.

- The old `[language: [label: count]]` file must still load; write the new format alongside.

## Step 7 — Latency guard and metrics (spec 1.7)

Files: `LSPCompletionProvider.swift` (deadline), `CompletionAggregator.swift` (generalize the
late-merge path from AI-only to any late provider), new
`CodeEdit/Features/Completion/CompletionMetricsStore.swift`, tests `CompletionAggregatorTests.swift`,
`CompletionMetricsStoreTests.swift`.

- Verify in the app with clangd on a large translation unit that typing stays fluid and the
  window updates when the server answers.

## Step 8 — Golden ranking cases

Files: `CodeEditTests/Features/Completion/Golden/` with 10–15 C++ scenarios covering
member access, scope access, type position, `case` labels, `#include`, and plain expression.

## Verification before reporting

- Full build, `swiftlint --strict` at the repo root and inside `CodeEditSourceEditor`.
- Run all completion tests plus the vendored package's `SuggestionCompletionTests`.
- Manual check in the running app (C++ file, clangd available): report each of the seven
  features as verified, not verified, or blocked, separately.
- Do not merge into `main`, do not push. Report back with the commit list.
