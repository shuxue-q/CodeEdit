# Changelog

## 0.4.3 - 2026-10-14

### Features
- Flutter: recognize Flutter projects from `pubspec.yaml`, locate the Flutter SDK from the login shell (with a per-workspace override), and find native CMake roots (`src/`, `cpp/`, `native/`, platform folders, `packages/*/src/`) so clangd gets the right compilation database.
- LSP: Dart analysis server, launched from the Flutter SDK's own `dart` binary, with auto-import on accept and incomplete-list refresh while typing.
- LSP: rust-analyzer support (resolved through `rustup which`), Cargo `linkedProjects` discovery, `cargo check` diagnostics on save.
- Completion: Dart and Rust intent recognition, keyword and snippet tables, and label details in the popup.
- Projects: hybrid Flutter + C++ + Rust workspaces. A project inventory finds Flutter/Dart packages, CMake projects and Cargo roots with their roles and build links; the project editor gains Overview, Flutter and Rust panes; settings live in `.codeedit/flutter-settings.json` and `cargo-settings.json`.
- Tasks: generated Flutter, Cargo and CTest tasks; hot reload and hot restart (toolbar bolt, ⌘\ / ⇧⌘\, on save); Cargo and Flutter output becomes problems in the Problems panel, Issues navigator and toolbar.

## 0.4.2 - 2026-10-10

### Features
- Completion: smart completion engine for C-family and CMake code: semantic ranking by the expected and receiver types, per-intent frequency and recency, a preselected best match, commit characters, call parentheses with parameter hints, `additionalTextEdits`, postfix templates after a dot, chain completion on Control-Shift-Space, document identifiers as a fallback source, and a latency budget with local metrics.
- Completion: AI backends (Anthropic and OpenAI-compatible) selectable in settings with per-backend keys, base URL and Test Connection; prompts carry the expected type, receiver type and function header; failures back off automatically.
- Completion: CMake intent recognition, keyword and snippet tables, and ranking, with integration tests against `neocmakelsp`.
- Themes: new editor color roles for fields, parameters, globals, namespaces, macros, preprocessor directives and primitive types, driven by tree-sitter captures and clangd semantic tokens; Qt Creator Light follows the Light (2024) scheme and One Dark Pro / One Dark Pro Darker get a distinct per-role palette.
- Themes: assigned-variable, function and operator roles.
- Navigator: New File / New Folder buttons above the project tree.
- Toolbar: the destination segment shows the CMake configure preset; toolbar controls share one set of design tokens.

### Fixes
- Editor: tree-sitter no longer lets the least specific capture win when several match the same range; semantic tokens are requested when the server attaches after the editor.
- Completion: main-actor isolation warnings, shared C-family language ids, Objective-C recognition, a one-second cap on the first list, and OpenAI request bodies per backend kind.
- Search: results are published before `search()` returns.
- Recents: double-slash file URLs open in their workspace and entries stay removable.
- Layout: workspace content width stays fixed during sidebar toggles; collapse animation unified.
- Navigator: rename field uses theme colors.

## 0.4.1 - 2026-10-01

### Features
- Completion: intent recognition. The editor works out what is being typed at the cursor (member access, include path, type name, new declaration name, comment, string, and more) and filters and ranks candidates accordingly; the popup no longer opens while typing where completions are unwanted, but can still be requested explicitly.

### Fixes
- Build: SwiftLint no longer lints agent worktrees under `.claude/` or `.build/`, which failed the build with thousands of violations from copied package checkouts.

## 0.4.0 - 2026-09-30

### Features
- Project navigator: toggle for hidden files, with per-project navigator visibility settings.
- Project settings: new Project Files, Version Control, and text-file editor panes; the CMake project editor moved into the shared Project Settings feature.
- CMake: project, preset, and build support, with a project editor and toolchain detection.
- LSP: server detection, hover documentation, diagnostics with a problems pane, and completion items mapped to SF Symbols with Xcode colors.
- Debugging: DAP-based C/C++ debugging via `lldb-dap`, with gutter breakpoints and a debug toolbar.
- Editor: reworked jump bar (symbols, counterpart files, issues), rainbow brackets, and Markdown preview.
- Navigators: issues, tests, debug, breakpoints, and reports navigators.
- macOS Tahoe-style toolbar, tab bar, navigator, inspector, and utility area.

### Improvements
- Replaced Liquid Glass chrome with Xcode-style toolbar capsules.
- Vendored `CodeEditLanguages`, `CodeEditSourceEditor`, and `CodeEditTextView` as local packages.
- Upgraded GRDB and ZIPFoundation.
- Completion keyword matching performance.
- Added a release workflow.

### Fixes
- SF Symbol rendering and alignment in completion labels.
- Git popup no longer appears when Source Control is disabled.
- Git status parsing handles null characters.
- Quick Open crash (missing undo manager registration).
- Alignment in the Git clone panel.
- Deprecation warnings, memory leak, and entitlements cleanup.
