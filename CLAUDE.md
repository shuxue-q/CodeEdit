# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

<!--
  AGENTS.md is the canonical, tool-agnostic guide shared by all coding agents. Claude Code
  auto-loads it only when no CLAUDE.md exists; this file's presence disables that, so the
  `@AGENTS.md` import below is what restores it. Keep the import; add only Claude-specific
  or supplementary notes below, without restating anything AGENTS.md already covers.
-->

@AGENTS.md

## Commands (supplements AGENTS.md)

Build into the repo's gitignored `DerivedData/` so incremental builds reuse the cache and the
app lands at a known path:

```bash
xcodebuild -project CodeEdit.xcodeproj -scheme CodeEdit -destination "platform=OS X,arch=arm64" -derivedDataPath DerivedData -skipPackagePluginValidation build
```

Launch the result with `open DerivedData/Build/Products/Debug/CodeEdit.app`.

Single test: reuse the same flags with `test` and narrow with `-only-testing`. The unit target
mixes XCTest (`-only-testing:CodeEditTests/<TestClass>/<testMethod>`) and Swift Testing
(`-only-testing:CodeEditTests/<Suite>/<function>()`):

```bash
xcodebuild -project CodeEdit.xcodeproj -scheme CodeEdit -destination "platform=OS X,arch=arm64" -derivedDataPath DerivedData -skipPackagePluginValidation test -only-testing:CodeEditTests/<TestClass>/<testMethod>
```

Vendored packages (`CodeEditSourceEditor`, `CodeEditTextView`, `CodeEditLanguages`) are not in
the app's test plan. Test them from their own directory with their own scheme, following
`CodeEditSourceEditor/.github/scripts/tests.sh` (same pattern for the other two; `.build/` is
gitignored):

```bash
cd CodeEditSourceEditor && xcodebuild -scheme CodeEditSourceEditor -derivedDataPath .build -destination "platform=macOS,arch=arm64" -skipPackagePluginValidation test
```

CodeGraph CLI, for when the MCP tool isn't loaded: `codegraph explore "<query>"`,
`codegraph node <symbol-or-file>` (one symbol's source with callers/callees, or a file with its
dependents), `codegraph status` (index freshness). `.codegraph/` is gitignored; if `codegraph
status` shows the index is stale, `codegraph sync` updates it incrementally (don't run
`codegraph init` or `codegraph index` unless asked).

## Architecture: how a workspace window is assembled

1. **Boot.** `CodeEditApp.init` registers `LSPService` and `DebugService.shared` in
   `ServiceContainer` (resolved elsewhere with the `@Service` wrapper) and touches
   `CodeEditDocumentController.shared` first so that subclass becomes the app's
   `NSDocumentController`. `Settings.shared` is a plain singleton, not a registered service.
   SwiftUI scenes cover only auxiliary windows (Welcome, About, Settings, Extension manager);
   workspace windows are AppKit, created by `NSDocument` window controllers.
2. **Shared services.** `LSPService`, `DebugService`, and app-wide notifications such as
   `.ceActiveTaskDidFinish` (posted with `object: nil`, workspace URL in `userInfo`) are shared
   by every open workspace window. Per-workspace consumers must filter by workspace URL — see
   `WorkspaceDocument.observeTaskReports(url:)` and `ReportStore`'s debug-session check.
3. **Opening.** `CodeEditDocumentController.openDocument(withContentsOf:display:completionHandler:)`
   turns a folder into a `WorkspaceDocument`; a file inside an already-open workspace becomes a
   tab in the nearest workspace (most shared path components); any other file opens as a
   standalone `CodeFileDocument` window (`WindowCodeFileView`). `AppDelegate` handles
   `codeedit://file/<path>:<line>:<column>` URLs.
4. **Per-workspace models.** `WorkspaceDocument.initWorkspaceState(_:)` creates
   `CEWorkspaceFileManager` (file tree + FSEvents; git events feed `SourceControlManager`),
   `SourceControlManager`, `SearchState`, `CEWorkspaceSettings`, `ReportStore`, `TaskManager`,
   and the CMake models when the root has a `CMakeLists.txt`; `EditorManager`,
   `UtilityAreaViewModel`, and `StatusBarViewModel` are owned by the document too.
5. **Window.** `WorkspaceDocument.makeWindowControllers()` → `CodeEditWindowController`
   (toolbar, panel toggles, `@IBAction` menu targets, command-palette entries via
   `CommandManager.shared`) → `CodeEditSplitViewController`: navigator | `WorkspaceView`
   (`CodeEdit/WorkspaceView.swift`: editor layout, utility area, status bar) | inspector.
6. **SwiftUI-in-AppKit rule.** Every `NSHostingView` root is wrapped in `SettingsInjector` and
   given the workspace models via `.environmentObject(...)` (see
   `CodeEditSplitViewController.viewDidLoad()`). A new hosted root must do the same, or
   `@EnvironmentObject` lookups crash at runtime and views using `@AppSettings` stop
   re-rendering on settings changes.
7. **Menus.** SwiftUI `.commands` (`CodeEditCommands`, `Features/WindowCommands/`) cannot see
   AppKit windows directly; they use `observeWindowController(_:)`
   (`KeyWindowControllerObserver`) to track the key window's `CodeEditWindowController`.
8. **Editor model.** `EditorManager.editorLayout` is a recursive `EditorLayout` enum
   (`.one(Editor)`, or `.horizontal`/`.vertical` holding `SplitViewData`); each `Editor` is a tab
   group with a temporary (preview) tab and back/forward history. Opening a tab calls
   `CEWorkspaceFile.loadCodeFile()`, which creates the `CodeFileDocument`, stores it on
   `file.fileDocument`, and registers it with the document controller; the document closes when
   the last tab showing that file closes. `CodeFileDocument.content` (`NSTextStorage`) is
   deliberately not `@Published` (per-keystroke string compares hang on large files) — observe
   edits through `contentCoordinator`.
9. **Editor stack layering** (where to change what): `CodeEditTextView` (text layout, selection,
   drawing) → `CodeEditSourceEditor` (`SourceEditor` SwiftUI wrapper, `TextViewController`,
   tree-sitter highlighting, gutter, find panel, completion popup) → the app's `CodeFileView`
   plus `Features/LSP` providers; `CodeEditLanguages` supplies grammars and queries.
10. **LSP flow.** `CodeFileDocument` posts `didOpenNotification` / `didCloseNotification`;
    `LSPService` observes them and keeps one `LanguageServer<CodeFileDocument>` per
    `ClientKey(languageId, workspacePath)`, started lazily on first open (workspace root, or the
    file's parent folder for standalone files). On open, the server attaches per-document state
    (`languageServerObjects`, including the semantic-token highlight provider). Diagnostics
    collect in `LSPService.diagnosticsStore`; CMake configure-preset changes reach `LSPService`
    via `CMakeWorkspace.configurePresetDidChangeNotification`; closing a workspace
    (`CodeEditDocumentController.removeDocument(_:)`) shuts its servers down.
11. **Tasks and terminals.** Tasks are stored in the workspace's `.codeedit/settings.json`
    (`CEWorkspaceSettings`). `TaskManager.executeActiveTask()` hands CMake build targets to
    `CMakeBuildController`; other tasks run as `CEActiveTask` in a SwiftTerm pseudo-terminal
    (`CEActiveTaskTerminalView`), with signals sent to the terminal's foreground process group;
    completion posts `.ceActiveTaskDidFinish`, which the workspace records in `ReportStore`.
    Utility-area terminal views are cached in `TerminalCache.shared` so shells survive SwiftUI
    view rebuilds; `WorkspaceDocument.close()` releases them.
12. **Git.** `SourceControlManager` → `GitClient` → `ShellClient`, which runs
    `/bin/zsh -lic "cd <dir>;git <args>"` (login shell, so the user's PATH applies). There is no
    libgit2 — escape anything interpolated into those command strings.

## State and persistence

- **Global settings**: `Settings.shared.preferences` (`SettingsData`) persists to
  `~/Library/Application Support/CodeEdit/settings.json`, autosaved with a 2-second throttle.
  Read it in SwiftUI with `@AppSettings(\.<page>.<key>)`, elsewhere with `Settings[\.<page>]`.
  Every settings struct implements `init(from:)` with `decodeIfPresent(...) ?? default`; keep
  that pattern when adding a key or page — a failed decode falls back to defaults, and the
  autosave then overwrites the user's settings file (see the doc comment on `SettingsData`).
- **Per-workspace files**, inside the opened folder: `.codeedit/settings.json` (project name,
  tasks; removed when empty) and `.codeedit/reports.json` (build/task/debug history, newest
  first, capped).
- **Per-window UI state** (open tabs/editor layout, utility-area size and collapse state,
  navigator/inspector collapse, window frame — the `WorkspaceStateKey` cases) lives in
  `UserDefaults` under `workspaceState-<workspace file URL>`; `EditorManager` and
  `UtilityAreaViewModel` restore it in `initWorkspaceState(_:)` and save it in `close()`.

## Repo conventions

- Design specs and implementation plans live in `docs/superpowers/specs/` and
  `docs/superpowers/plans/` with `YYYY-MM-DD-<topic>` filenames; `.superpowers/sdd/` holds
  working files that its own `.gitignore` ignores.
