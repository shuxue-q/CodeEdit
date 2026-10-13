# Flutter + C++ Hybrid Projects and Dart Completion — Design

Date: 2026-10-13
Status: planned; implemented across `feat/dart-lsp`, `feat/flutter-project`, and
`feat/dart-completion-intent`.
Builds on `2026-09-28-completion-aggregator-design.md`,
`2026-10-09-smart-completion-engine-design.md` and `2026-10-09-cmake-completion-design.md`.

## Problem

CodeEdit already highlights Dart (the vendored `tree-sitter-dart` grammar) and maps `.dart`
files to the LSP language id `dart`, but no Dart language server is ever started:
`LanguageServerDetector.supportedServers` knows only `clangd` and `neocmakelsp`, so opening a
Dart file silently gets no completion, diagnostics, hover or semantic tokens. The intent
recognizer has rules for the C family and CMake only, so even with a server Dart candidates
would all be weighted with the flat 0.5 of `.unknown`. Flutter projects that embed C++ (an FFI
plugin, or an app with a native core built by `hook/build.dart`) are recognized as CMake
projects only when the `CMakeLists.txt` sits at the workspace root.

## Decisions (agreed 2026-10-13)

- Target layout: Flutter FFI plugins and apps. Sample workspace: `~/Desktop/OmniExam`
  (root `CMakeLists.txt` + `CMakePresets.json`, native code in `cpp/`, Dart FFI bindings in
  `lib/native_bridge/`, `hook/build.dart` builds the C++ through CMake). The
  `flutter create --template=plugin_ffi` layout (`src/CMakeLists.txt`, no root list file) is
  the second supported shape.
- C++ completion uses the macOS host compile flags. No Android NDK toolchain support.
- The Flutter SDK is the `flutter` found on the login-shell `PATH`. No fvm support.
- The Dart analysis server analyzes only projects with open files
  (`onlyAnalyzeProjectsWithOpenFiles: true`) to keep CPU and memory down.
- Out of scope for this round: Flutter run/device picker tasks, hot reload, Dart/Flutter
  debugging (`flutter debug_adapter`).

## What the Dart analysis server offers

Probed with `dart language-server --protocol=lsp` from Flutter 3.47.0 / Dart 3.13.0:

- Completion trigger characters `.` `=` `(` `$` `"` `'` `{` `/` `:`, `resolveProvider: true`,
  `labelDetailsSupport: true`. Unimported-library suggestions carry their auto-import
  `additionalTextEdits` and documentation only after `completionItem/resolve`.
- Signature help on `(`, retrigger on `,`. Hover, definition. Semantic tokens: full (no
  delta) and range, 19 token types. Incremental document sync.
- Dart-specific notifications the client must ignore: `$/analyzerStatus`,
  `dart/textDocument/publishClosingLabels`, `dart/textDocument/publishOutline`,
  `dart/textDocument/publishFlutterOutline`.
- Initialization options (`initializationOptions`): `onlyAnalyzeProjectsWithOpenFiles`,
  `suggestFromUnimportedLibraries`, `closingLabels`, `outline`, `flutterOutline`.

## Part 1 — Dart language server (`feat/dart-lsp`)

Files: `Features/LSP/Service/LanguageServerDetector.swift`, `LSPService+Detection.swift`,
`LanguageServer/LanguageServer.swift` (`getInitParams`), `Settings/Pages/LSPSettings/`.

- `SupportedServer(executable: "dart", languageIds: ["dart"],
  arguments: ["language-server", "--protocol=lsp", "--client-id=codeedit"])`.
- SDK resolution (off the main actor, in the login-shell environment): locate `flutter` on
  `PATH`, resolve symlinks to the SDK root, and use
  `<sdk>/bin/cache/dart-sdk/bin/dart` when it exists. Fall back to `dart` on `PATH`. Never
  launch through the `flutter`/`dart` bash wrapper when the real binary is available (slower
  start, prints version-check noise, may try to download).
- `getInitParams` gains per-language `initializationOptions`. For `dart`:
  `onlyAnalyzeProjectsWithOpenFiles: true`, `suggestFromUnimportedLibraries: true`,
  `closingLabels: false`, `outline: false`, `flutterOutline: false`.
- Client `resolveSupport.properties` adds `additionalTextEdits` so Dart defers import edits
  to resolve. Verify `needsResolveBeforeApply` (`LSPCompletionProvider+Apply`) resolves Dart
  items and that accepting an unimported symbol inserts the `import`.
- `LSPService+Events.handleNotification` must ignore unknown/Dart-specific notifications
  without logging errors per keystroke.
- LSP settings page lists the Dart server with its detected path and a manual override, like
  the other rows.
- Large completion lists: Dart returns many items with `isIncomplete`; confirm the
  `LSPCompletionProvider` deadline (800 ms) and the aggregator's first-list budget keep the
  UI responsive, and cap per-request mapping if needed.
- Semantic tokens: confirm the 19 Dart token types map onto the editor's `SemanticTokenMap`
  and theme symbol roles; `requests.delta` is advertised by the client but Dart serves
  `full` without delta, which the existing code must tolerate.

Verification: open `~/Desktop/OmniExam/lib/main.dart`, see diagnostics for that file only,
type `context.` and `Text(` and accept items, accept an unimported symbol and see the
import added, hover a Flutter widget, confirm semantic highlighting.

## Part 2 — Flutter project model (`feat/flutter-project`)

Files: new `Features/Flutter/` (`Models/FlutterProject.swift`,
`Models/FlutterSDK.swift`, `Models/PubspecParser.swift`, `Views/FlutterProjectPane.swift`),
`Documents/WorkspaceDocument/WorkspaceDocument.swift`, `CMake/Models/CMakeProject.swift`,
`CMake/Models/CMakeCompilationDatabase.swift`, the project editor.

- `FlutterProject.isFlutterProject(at:)`: a root `pubspec.yaml` whose `dependencies` contain
  `flutter` (`sdk: flutter`) or whose `flutter:` section has `plugin.platforms.*.ffiPlugin`.
  Minimal line-based YAML reading (name, version, flutter dependency, plugin platforms); no
  YAML dependency, no tool execution. Discovery runs off the main actor like CMake's.
- Native CMake root discovery, in order: the workspace root `CMakeLists.txt` (existing
  behavior), then `src/`, `cpp/`, `native/`, `linux/`, `windows/`, `macos/` and
  `packages/*/src/` containing a `CMakeLists.txt`. The first match is the active native root;
  the pane lets the user pick another when several exist. The choice persists like CMake
  preset selection (`UserDefaults`, keyed by workspace path).
- `CMakeProject`/`CMakeWorkspace`/`CMakeCompilationDatabase` accept a source directory other
  than the workspace root. `compilationDatabaseBinary` resolves the workspace path to the
  active native root before asking for a database, so clangd gets `compile_commands.json`
  for `src/` layouts. Root-level projects keep working unchanged.
- The compilation database honours the selected configure preset's binary directory (OmniExam:
  `build/macos-debug` already contains `compile_commands.json`, reuse it rather than
  configuring).
- Project editor: a "Flutter" pane showing the project name, Flutter SDK path and version
  (from `<sdk>/version`), the discovered native roots and the active one.
- `docs/flutter-projects.md` documents the recognized layouts and the native-root rule.

Verification: open `~/Desktop/OmniExam`, see the Flutter pane with the SDK and `cpp/` listed,
open `cpp/src/core.cpp` and get clangd completion with the project's includes. Create a
`flutter create --template=plugin_ffi` project in a temp directory, open it, confirm `src/`
is the native root and clangd starts with a database.

## Part 3 — Dart completion intent (`feat/dart-completion-intent`)

Files: `Features/Completion/Intent/` (new `DartTokenRules.swift`, `DartKeywords.swift`;
`CompletionLineScanner.swift` operators; `CompletionIntentRecognizer.swift` dispatch;
`CompletionIntentPolicy.swift` weights), `Providers/DartCompletionTables.swift`,
`TreeSitterSnippetProvider.swift` tables, tests under `CodeEditTests/Features/Completion/`,
`docs/code-completion.md`.

- Scanner: add `?.`, `..`, `?..`, `=>`, `??`, `??=`, `...`, `...?`.
- Intents for Dart (shared `CompletionIntent` cases, as CMake did):

| Site | Example | Intent |
| --- | --- | --- |
| Member access | `context.`, `a?.`, `b..` | `.memberAccess` |
| Type position | `new `, `is `, `as `, `extends `, `implements `, `with `, `List<`, `on ` | `.typeName` |
| New declaration name | `var `, `final `, `const `, `late `, `Widget ` | `.declarationName` |
| Argument list | `Text(`, `Padding(padding: x, ` | `.argument` |
| Named argument value, assignment, return | `child: `, `= `, `return ` | `.expression` |
| Statement start inside a body | `  ` in a function body | `.statement` |
| File scope | `cl` | `.topLevel` |
| Interpolation inside a string | `'$na`, `'${us` | `.variableReference` |
| String, comment, number | `'...`, `//`, `///`, `42` | `.string` / `.comment` / `.numberLiteral` |

- `CompletionIntentPolicy.weight` branches on `languageId == "dart"` for `.argument`
  (server items of kind `.field`/named-argument first; snippets excluded) and for
  `.statement`/`.topLevel` (keywords and snippets allowed, like the C family).
- Tables: Dart keywords; snippets `stless`, `stful`, `build`, `for`, `forin`, `if`,
  `switch`, `try`, `main`, in the existing `SnippetText` format.
- The recognizer uses the vendored Dart grammar's node names for scope (string, comment,
  arguments, function body, class body) and the token rules first, as for C.
- Unit tests mirror the CMake ones: scanner operators, each intent row above, and that C and
  CMake behavior is unchanged.

Verification: with Part 1 merged, type a widget tree in OmniExam and confirm named
arguments lead after `(` and `,`, members lead after `.`, no popup inside strings, and
`$` inside a string offers variables.

## Constraints

- No Liquid Glass, no new dependencies, SwiftLint `--strict` clean, public declarations
  documented. Keep detection and discovery off the main actor.
- C, C++ and CMake behavior does not change; their tests stay green.
- Settings structs keep the `decodeIfPresent ... ?? default` pattern.
