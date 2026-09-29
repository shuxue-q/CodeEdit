# Completion Aggregator — Implementation Plan

Spec: `docs/superpowers/specs/2026-09-28-completion-aggregator-design.md`

The working tree contains a large amount of uncommitted work, including in-flight completion
changes. Do not revert, reformat, stash, or commit it. Edit only what each task needs. The Xcode
project uses synchronized folders, so new files under `CodeEdit/` and `CodeEditTests/` are
picked up without editing `project.pbxproj`.

Build and test commands are in the repo's `CLAUDE.md`. Always pass `-derivedDataPath DerivedData`.

## Tasks

1. **Package badge API** (`CodeEditSourceEditor`)
   - Add `CodeSuggestionBadge.swift` in `CodeSuggestion/Model/`, and add `badge` to
     `CodeSuggestionEntry` with a default of nil in a public extension. Add doc comments.
   - Render the badge at the far right in `CodeSuggestionLabelView`, in both layouts
     (`showsTrailingDetail` true and false), with a fixed-width column and
     `.accessibilityLabel`.
   - Add a package test. Run the package tests and its SwiftLint from `CodeEditSourceEditor/`.
2. **Pipeline core** (pure, no AppKit): `CompletionSource`, `CompletionCandidate`,
   `CompletionPayload`, `SyntacticContext`, `CompletionContext`, `FuzzyMatcher`,
   `CompletionDeduplicator`, `RankingWeights` + `CompletionRanker`, and
   `CompletionPresenter` + `AggregatedCompletionEntry`. Write the Swift Testing suites first
   (TDD), then implement.
3. **Frequency store**: `CompletionFrequencyStore` with a protocol so tests can use an
   in-memory implementation. Include a round-trip and decay test.
4. **Snippet helpers**: move `parseSnippet`/`stripSnippetSyntax` into `SnippetText`
   (internal, static). `LSPCompletionDelegate` then calls it.
5. **LSP provider**: rename/refactor `LSPCompletionDelegate` into `LSPCompletionProvider`
   conforming to `CompletionProvider`. Keep the request, reopen-retry, `#include`
   augmentation, and apply logic intact. Filtering moves to the pipeline. Map each
   `CompletionItem` to a `CompletionCandidate` (`filterText` = `item.filterText ?? label`,
   `sortText`, `kind` via `LSPCompletionEntry.category(for:)`). Update the existing tests
   that reference `LSPCompletionDelegate`.
6. **Syntactic context resolver + snippet provider**: `SyntacticContextResolver` (inject
   a `nodeTypesAt: (Int) -> [String]` closure so it can be tested without a live
   TreeSitterClient; the production closure uses `treeSitterClient.nodesAt(location:)`), and
   `TreeSitterSnippetProvider` with the C/C++ tables.
7. **Aggregator**: `CompletionAggregator: CodeSuggestionDelegate` handles the fan-out with
   deadlines, late-AI merging, synchronous re-filtering in `completionOnCursorMove`, apply and
   resolve routing, frequency recording, and window-close cleanup. Wire it in `CodeFileView`
   (it needs the view's `treeSitterClient`).
8. **Claude provider + settings**: `ClaudeCompletionProvider` (URLSession, injectable
   `URLSession` for tests), the `AICompletionSettings` sub-struct on `TextEditingSettings`
   (following the `decodeIfPresent` pattern), a Keychain-backed key, and the settings UI
   section. Tests use a `URLProtocol` stub covering request headers and body, a successful
   decode, a refusal, and an HTTP error.
9. **Verification**: build the app; run the focused tests
   (`-only-testing:CodeEditTests/<each new suite>`, `LSPCompletionTests`,
   `LSPCompletionOriginTests`); run the package tests; run `swiftlint --strict` at the root and
   in `CodeEditSourceEditor/`. Report pass, fail, and skip for each one separately.

## Style reminders

- Every new file starts with the standard header (`//  File.swift`, `//  CodeEdit`,
  `//  Created by CodeEdit Contributors on 9/28/26.`).
- 4-space indent, and doc comments on every non-private declaration (`missing_docs` is on).
- No Liquid Glass APIs.
- Never interpolate user text into shell strings. There are no shell calls in this feature.
