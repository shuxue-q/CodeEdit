# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Rules (mandatory)

- **Never develop directly on `main`.** Before making any code change, create a dedicated
  branch cut from the current `main` (`git switch main && git switch -c <prefix>/<short-topic>`).
- **Choose the branch prefix automatically from the task's intent:**
  - `feat/` — new features or capabilities
  - `fix/` — bug fixes
  - `refactor/` — code restructuring without behavior change
  - `UI/` — UI/UX adjustments (layout, styling, interaction polish)

  Use a short kebab-case topic after the prefix (e.g. `fix/lsp-restart-crash`,
  `UI/toolbar-spacing`). If a task spans several intents, pick the dominant one.
- **Never merge any branch into `main`, and never push to any remote, without explicit
  confirmation and instruction from the user in the current conversation.** Finishing a task
  means committing on the feature branch (when asked) and reporting back; merging and pushing
  are separate, user-initiated steps. Approval for one merge or push does not carry over to
  later ones.
- When the user does ask to merge, use `git merge --no-ff <branch>` on `main` so feature
  history stays visible.
- Remotes: `origin` is the project's own GitHub repository; `upstream` is
  `CodeEditApp/CodeEdit` (fetch only — never push to it).

## Working Rules

- Inspect `git status --short --branch` before editing. Preserve existing
  changes and untracked files; keep the diff focused on the requested task.
- State assumptions and a short verification plan before multi-step work.
  Clarify material ambiguity; prefer the simplest implementation that meets
  the request. Avoid unrelated refactoring or formatting.
- For UI changes, propose the layout and interaction flow in an ASCII sketch
  before implementing it. Match the existing SwiftUI/AppKit conventions.
- Documentation-only tasks should remain documentation-only. Do not commit,
  push, or discard work unless requested.

### Liquid Glass

CodeEdit does **not** use Apple Liquid Glass. Keep Sequoia chrome on macOS 26
and later: rectangular tabs, `NSVisualEffectView` / `EffectView` materials, and
custom SwiftUI toolbar controls. Do not add Liquid Glass to match system apps.

Forbidden APIs and patterns:

- `NSGlassEffectView`, `NSGlassEffectContainerView`
- SwiftUI `.glassEffect`, `.buttonStyle(.glass)` / `.glassProminent`
- `NSToolbarItem.Style.prominent`, glass `backgroundTintColor`, and any
  Solarium / Liquid Glass API
- `NSToolbarItem.isBordered = true` on macOS 26 (AppKit puts glass behind
  bordered items). Use custom SwiftUI / `NSHostingView` chrome instead.

`#available(macOS 26, *)` is allowed only for layout or API bugfixes, never to
adopt glass. Do not use `UIDesignRequiresCompatibility` or
`com.apple.SwiftUI.DisableSolarium` as a substitute for this rule.

## Project Overview

**CodeEdit** is a free, open-source, native code editor for macOS, written
entirely in Swift. It aims to offer a lightweight, TextEdit-like experience that
can scale up to an Xcode-like IDE, while staying true to Apple's Human
Interface Guidelines. Features include syntax highlighting, code completion
(via LSP), project find and replace, snippets, an integrated terminal, task
running, git integration, extensions, and more.

- License: MIT (`LICENSE.md`)
- Status: in active development; not yet recommended for production use.
- Repository: https://github.com/CodeEditApp/CodeEdit
- Language of code, comments, and documentation: **English**.

## Technology Stack

- **Language**: Swift 5 (`SWIFT_VERSION = 5.0`), using SwiftUI for most UI with
  AppKit interop (`NSApplicationDelegateAdaptor`, `NSViewControllerRepresentable`, etc.).
- **Platform**: macOS only; minimum deployment target **macOS 14.0**.
- **Build system**: The app builds through `CodeEdit.xcodeproj`. There is **no
  root `Package.swift`**; the three vendored packages have their own manifests.
  Remote Swift Package Manager dependencies are resolved by Xcode and pinned in
  `CodeEdit.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- **Key dependencies** (see `Package.resolved` for exact pins):
  - `CodeEditTextView` — custom text view, vendored locally in
    `CodeEditTextView/` and referenced by `CodeEditSourceEditor/Package.swift`.
    Edit this copy for mouse selection behavior; do not re-add the remote package.
  - `CodeEditSourceEditor` — the source editor (completion window, etc.).
    **Vendored locally** in `CodeEditSourceEditor/` at the repo root as a Swift
    package (added to the project as a local package reference replacing the
    remote `CodeEditApp/CodeEditSourceEditor` dependency; do not re-add the
    remote package).
  - `CodeEditLanguages` — tree-sitter-based syntax highlighting. **Vendored
    locally** in `CodeEditLanguages/` at the repo root as a Swift package
    (added to the project as a local package reference, which overrides the
    remote `CodeEditApp/CodeEditLanguages` dependency of
    `CodeEditSourceEditor`; do not re-add the remote package). The tree-sitter
    grammars ship as a prebuilt `CodeLanguagesContainer.xcframework.zip`
    binary target inside the package. When changing grammars, run
    `./build_framework.sh` from **inside `CodeEditLanguages/`**; the script
    rebuilds the binary and replaces generated query resources.
  - `CodeEditKit` — extension API framework (bundled as a framework in the app).
  - `SwiftTerm` (CodeEdit fork, branch `codeedit`) — terminal emulator.
  - ChimeHQ stack (`LanguageServerProtocol`, `LanguageClient`, `JSONRPC`,
    `SwiftTreeSitter`, `TextFormation`, …) — LSP client and text handling.
  - `Sparkle` — automatic software updates.
  - `GRDB.swift` — SQLite (used by the search indexer).
  - `WelcomeWindow`, `AboutWindow`, `CodeEditSymbols`, `SwiftUI-Introspect`,
    `ZIPFoundation`, `swift-snapshot-testing` (tests), `SwiftLintPlugin` (build
    tool plugin), and others.
- **App model**: document-based app. `CodeEditApp` (`CodeEdit/CodeEditApp.swift`)
  is the `@main` entry point; `AppDelegate` handles app lifecycle. Documents are
  managed by `CodeEditDocumentController`; `WorkspaceDocument` represents an
  open project/workspace and `CodeFileDocument` a single file.
- **Dependency injection**: a lightweight service container lives in
  `CodeEdit/Utils/DependencyInjection` (`ServiceContainer.register(...)` in the
  app init, `@LazyService` / `@Service` property wrappers at call sites).
  Singleton services such as `Settings.shared` and `LSPService` are registered
  at launch.

## Project Layout

- `CodeEdit/` — main app target.
  - `CodeEditApp.swift`, `AppDelegate.swift` — entry point and lifecycle.
  - `Features/` — all app features, one directory per feature. Major ones:
    - `CEWorkspace` — workspace models (`CEWorkspaceFile`, file management).
    - `Documents` — document controller, `WorkspaceDocument`, `CodeFileDocument`,
      and the Spotlight-style file indexer.
    - `Editor` — editor area, tabs, and file editing UI.
    - `LSP` — language server detection/configuration, per-document clients,
      completion, hover documentation, and `Diagnostics/LSPDiagnosticsStore.swift`.
      Server settings live in `Settings/Pages/LSPSettings/`.
    - `CMake` — static project/preset parsing, workspace preset selection,
      compilation database generation, build execution, and build-output parsing.
    - `NavigatorArea` / `InspectorArea` / `UtilityArea` / `StatusBar` /
      `ActivityViewer` — the window's sidebars, bottom panel, and status UI.
      The navigator tab bar (project, source control, bookmarks, search,
      issues, tests, debug, breakpoints, reports) is defined by
      `NavigatorArea/Models/NavigatorTab.swift`; `IssuesNavigator` and
      `UtilityArea/ProblemsUtility/` share `CodeEditUI/Views/DiagnosticsListView`
      to display problems; `ReportsNavigator/Models/ReportStore.swift` records
      build/task/debug history per workspace in `.codeedit/reports.json`;
      `ActivityViewer/Views/` contains the toolbar capsules and controls.
    - `SourceControl` — git integration.
    - `TerminalEmulator`, `Tasks` — integrated terminal and task runner.
    - `Debugging` — DAP-based C/C++ debugging via the system `lldb-dap`
      (located through the login shell PATH with an `xcrun --find` fallback).
      `DAP/` contains the wire-protocol client; `Service/DebugService` owns the
      session (launch, breakpoints, stepping, watches); `BreakpointStore`
      persists gutter breakpoints (0-based lines per file path);
      `BreakpointCoordinator` bridges gutter clicks and the current-line
      marker in the vendored editor (`GutterView.breakpointLines` /
      `currentDebugLine`); `Views/` implements the `Debugger` utility tab.
    - `Search`, `OpenQuickly` — project find/replace and quick open.
    - `Settings` — settings window, models, and `SoftwareUpdater` (Sparkle).
    - `CodeEditUI` — shared UI components (views, styles) used across features.
    - `Commands`, `WindowCommands`, `Keybindings`, `Extensions`, `Welcome`,
      `About`, `Feedback`, `Notifications`, `SplitView`, `CEWorkspaceSettings`.
  - `Utils/` — cross-cutting helpers: `DependencyInjection`, `Extensions`,
    `KeyChain`, `ShellClient`, `Formatters`, `Environment`, `Protocols`.
  - `Localization/` — `en.lproj` strings plus `Localized+Ex.swift`.
  - `ShellIntegration/` — shell scripts bundled for terminal integration.
  - `Assets.xcassets`, `Info.plist`, `CodeEdit.entitlements`. Channel app
    icons are Icon Composer `.icon` bundles in `Assets.xcassets`
    (`CodeEditDevIcon`, `CodeEditAlphaIcon`, `CodeEditBetaIcon`,
    `CodeEditPreIcon`, `CodeEditIcon`). `CE_APPICON_NAME` selects one per
    configuration.
- `CodeEditTests/` — unit and integration tests using XCTest and Swift Testing,
  mirroring the feature layout (`Features/…`, `Utils/…`).
- `CodeEditUITests/` — XCUITest UI tests; see `CodeEditUITests/UI TESTING.md`
  for conventions (helpers `App.swift`, `ProjectPath.swift`, `Query.swift`).
- `OpenWithCodeEdit/` — Finder Sync extension target ("Open With CodeEdit"),
  embedded in the app bundle.
- `CodeEditLanguages/` — vendored Swift package (local package reference in
  the Xcode project) providing tree-sitter syntax highlighting languages.
  Edit this in-tree copy for app changes; Xcode resolves it through the local
  override. It is excluded from the repo-wide `.swiftlint.yml` (it carries its
  own config).
- `CodeEditSourceEditor/` — vendored Swift package (local package reference in
  the Xcode project) providing the source editor, including the completion
  suggestion window. Maintained in-tree; the GitHub
  `CodeEditApp/CodeEditSourceEditor` repo is no longer used. It is excluded
  from the repo-wide `.swiftlint.yml` (it carries its own config).
- `CodeEditTextView/` — vendored Swift package providing text layout, mouse
  selection, and drawing. `CodeEditSourceEditor` depends on this local copy.
  It has its own SwiftLint configuration and tests.
- `Configs/` — shared `.xcconfig` files: `Debug`, `Alpha`, `Beta`, `Pre`,
  `Release`. These set per-channel app icons (`CE_APPICON_NAME`), version
  postfixes, and copyright.
- `DefaultThemes/` — bundled `.cetheme` editor themes.
- `AppCast/` — Jekyll site that generates the Sparkle `appcast.xml` update feed.
- `Documentation.docc/` — DocC documentation catalog.
- `docs/cmake-project-presets.md` — CMake settings, build controls, problems,
  and compilation database behavior. Check current source when updating it.
- `CodeEditTestPlan.xctestplan` — the test plan referenced by the `CodeEdit`
  scheme (includes both unit and UI test targets; some legacy snapshot tests
  are listed as skipped).
- `CodeEditUI/` — contains only a stray `src/Preferences/ViewOffsetPreferenceKey.swift`
  that is **not** part of the Xcode project; treat it as legacy. The live shared
  UI code is `CodeEdit/Features/CodeEditUI`.

## CMake and LSP Boundaries

- `CMakeProject` recognizes a root `CMakeLists.txt`; `CMakeListParser`,
  `CMakePresetsParser`, and `CMakePresetExpansion` read metadata and presets
  without executing CMake. Keep discovery off the main actor and expose parse
  errors through workspace settings. `CMakeWorkspace` stores selections locally.
- Execution has separate entry points: `CMakeBuildController` configures when
  needed and builds; `CMakeCompilationDatabase` can run configure before clangd
  starts. Static discovery does not imply that opening C-family files is free
  of configure side effects. Preserve the selected preset's build directory and
  user-supplied `--compile-commands-dir` arguments.
- `LanguageServerDetector` locates `clangd` and `neocmakelsp` in the user's login
  shell environment; detection must run off the main actor. CodeEdit does not
  install these tools. Explicit server paths and arguments come from LSP settings.
- Document LSP attachment is language-driven and also works for standalone files,
  using their parent directory as the root. Keep CMake completion independent of
  CMake workspace discovery. App-side completion is under `LSP/Features/Completion/`;
  popup state and triggers live in the local `CodeEditSourceEditor` package's
  `CodeSuggestion/Model/` and `Filters/` directories. Hover is under `LSP/Features/Hover/`.

## Code Navigation and Search

This repository is indexed by the **CodeGraph MCP service** (the `.codegraph/`
index directory exists at the repo root). When the `mcp__codegraph__*` tools
are available:

- **Always prefer `mcp__codegraph__codegraph_explore` as the first tool** for
  any code question or lookup: how something works, where a symbol is
  defined/used, architecture and call flows, or surveying the symbols you are
  about to change. It returns the relevant source in one call and is cheaper
  and more accurate than a search/read loop.
- The query can be a natural-language question, symbol names, or file names
  (e.g. `"WorkspaceDocument openFile"`, `"how does the LSP client attach to
  documents"`).
- If the MCP tool is unavailable, use `codegraph explore "<query>"` from the
  repository root. Do not initialize or rebuild the index unless requested.
- Use `rg` or direct reads for non-code files, exact literal matches, generated
  artifacts, or when CodeGraph is unavailable or cannot answer. Honor stale-file
  or disabled-sync warnings by reading the affected files directly. CodeGraph
  navigation does not replace build, test, or lint verification.

## Xcode MCP

When Xcode MCP tools are available and authorized:

- Select this checkout with `XcodeListWorkspaces` and the returned
  `workspaceIdentifier` (or the absolute `CodeEdit.xcodeproj` path). When opening
  is needed, use `XcodeOpenWorkspace`; first use may require Xcode authorization.
  Do not reuse identifiers from earlier sessions.
- Confirm the active scheme, destination, and test plan with `XcodeListSchemes`,
  `XcodeListRunDestinations`, and `XcodeListTestPlans`. Use `GetTestList` to discover
  test identifiers before `RunSomeTests`; `RunAllTests` follows the active plan.
- `BuildProject` performs a build. Xcode file tools use project-organization
  paths, which can differ from filesystem paths. If MCP access is unavailable,
  use local project files and the command-line workflow below.

## Build and Test Commands

Requirements: macOS with a recent Xcode (the project uses Swift 5 / macOS 14
SDK features) and, for the command line, `xcbeautify`/`swiftlint` if you want
CI-parity output.

- Open in Xcode: `open CodeEdit.xcodeproj`, select the **CodeEdit** scheme,
  build/run with ⌘B / ⌘R.
- Build from the repository root on Apple Silicon:
  ```bash
  xcodebuild -project CodeEdit.xcodeproj -scheme CodeEdit \
             -destination "platform=OS X,arch=arm64" \
             -skipPackagePluginValidation build
  ```
- Build & run all tests from the command line (same as CI):
  ```bash
  set -o pipefail
  xcodebuild -scheme CodeEdit \
             -destination "platform=OS X,arch=arm64" \
             -skipPackagePluginValidation \
             clean test | xcbeautify
  ```
  (`-skipPackagePluginValidation` is required for the SwiftLint build-tool
  plugin.) CI runs `bash .github/scripts/test_app.sh arm` on Apple Silicon;
  omit `arm` for the script's Intel (`x86_64`) path. This is a clean test run;
  omit `clean` for normal incremental iteration.
- Focused test example:
  ```bash
  xcodebuild -project CodeEdit.xcodeproj -scheme CodeEdit \
             -destination "platform=OS X,arch=arm64" \
             -skipPackagePluginValidation \
             -only-testing:CodeEditTests/CMakeProjectTests test
  ```
- Lint:
  ```bash
  swiftlint --strict
  ```
  SwiftLint also runs automatically as a build phase plugin when building in
  Xcode; violations appear as Xcode warnings/errors. The root lint configuration
  excludes the three vendored packages: run lint from the affected package directory
  with its own configuration when changing package code.

Build output belongs in ignored `DerivedData/` or a task-specific temporary
directory (`-derivedDataPath`), not in source folders. Do not delete shared build
caches to work around a failure without checking their scope.

## Code Style Guidelines

Enforced by SwiftLint (`.swiftlint.yml`) — the CI lint job runs with `--strict`,
so **resolve all SwiftLint violations before submitting a PR** (TODO comments
are the only accepted warning).

- Indent with **spaces, never tabs** (custom `spaces_over_tabs` rule; 4 spaces
  per the project's Xcode settings and existing code).
- Disabled rules: `todo`, `trailing_comma`, `nesting`.
- Opt-in rules include `attributes`, `empty_count`, `closure_spacing`,
  `modifier_order`, `missing_docs`, `multiline_parameters_brackets`, and
  `multiline_arguments_brackets` — note `missing_docs`: **public declarations
  must have documentation comments**. Document your code thoroughly; the
  contribution guide explicitly requires it.
- Identifiers `id` and `vc`, and the symbols `$` and `_`, are explicitly
  allowed despite length rules.
- Follow the existing file organization: every source file starts with the
  standard header comment (`//  FileName.swift`, `//  CodeEdit`, creator/date).
  New feature code goes in a matching subdirectory of `CodeEdit/Features/`;
  shared helpers go in `CodeEdit/Utils/`; shared UI in `CodeEdit/Features/CodeEditUI/`.
- Follow Apple's Human Interface Guidelines for UI work, and prefer SwiftUI
  unless AppKit is genuinely needed.
- The full style guide is in the wiki:
  https://github.com/CodeEditApp/CodeEdit/wiki/Code-Style
- Localization PRs are currently **not accepted** (see `CONTRIBUTING.md`).

## Testing Instructions

- The app's test plan contains `CodeEditTests` (XCTest and Swift Testing) and
  `CodeEditUITests` (XCUITest). Both run through `CodeEditTestPlan.xctestplan`
  in the `CodeEdit` scheme; the full test command respects that plan's exclusions.
- Each vendored package also has a `Tests/` directory and its own test target;
  these are not listed in the app's test plan. Verify package changes separately.
  `CodeEditSourceEditor/Package.swift` still declares a remote `CodeEditLanguages`
  dependency: standalone package testing may resolve it instead of the app's
  local override. Check which sources are actually tested.
- Unit test utilities: `withTempDir`, `waitForExpectation` helpers in
  `CodeEditTests/Utils`.
- UI tests (see `CodeEditUITests/UI TESTING.md`):
  - Launch the app in tests via the `App` enum, preferably
    `App.launchWithTempDir()` which creates an isolated temporary workspace
    (cleaned up automatically). Avoid `App.launchWithCodeEditWorkspace` — it is
    legacy, flaky, and risks modifying this very repository.
  - Put long XCUIElement queries behind static methods on the `Query` enum to
    keep tests readable.
- Snapshot testing uses `pointfreeco/swift-snapshot-testing` (a number of
  legacy snapshot tests are skipped in the test plan).
- CMake parser/build tests are in `CodeEditTests/Features/CMake/`. LSP integration
  tests in `LanguageServer+CMakeIntegration.swift` and
  `LanguageServer+ClangdCompilationDatabase.swift` under `CodeEditTests/Features/LSP/`
  launch real tools; relevant tests skip when `neocmakelsp`, `cmake`, or `clangd`
  cannot be found. Report skips separately from passes.
- Completion changes need the full editor interaction verified: type `CMAKE_`
  inside `set()` or type `point.`, inspect the popup, filter, and accept an item.
  Protocol responses and formatting tests alone do not verify that interaction.
- Report focused tests, builds, lint, and app/UI checks separately, including
  anything skipped, unrun, or blocked by the environment. Documentation-only
  changes need path, Markdown, and diff checks; they do not require app tests.
- CI requires all tests to pass before a PR can be merged.

## CI / CD and Deployment

All GitHub Actions workflows live in `.github/workflows/`. Build, test, lint,
and version-bump jobs use **self-hosted macOS runners**; appcast, release-note,
and issue/project automation also use `ubuntu-latest` runners.

- `release.yml` — on `v*.*.*` tag pushes or manual dispatch (GitHub-hosted
  Apple Silicon runner): builds an ad-hoc-signed `Release` app with
  `CODE_SIGNING_ALLOWED=NO`, packages `CodeEdit-<tag>-arm64.dmg` with an
  `/Applications` symlink, generates a changelog from commits since the
  previous tag, and publishes it with `gh release create`.
- `CI-pull-request.yml` — on every PR to `main`: SwiftLint (`lint.yml`,
  `swiftlint --strict`), then the full test suite (`tests.yml`, which also
  verifies `CFBundleShortVersionString` exists via
  `.github/scripts/test_version_number.sh`).
- `CI-pre-release.yml` — manual dispatch: lint → test → `pre-release.yml`,
  which archives with the `Pre` configuration, codesigns (hardened runtime),
  builds and notarizes a DMG (`create-dmg`, background from
  `Resources/dmgBackground.png`), updates the Sparkle appcast (EdDSA-signed,
  `dev` channel), uploads dSYMs, and creates a draft GitHub release.
- `appcast.yml` — publishes the Sparkle appcast site from `AppCast/`.
- `release-drafter.yml`, `CI-bump-build-number.yml`, `CI-release-notes.yml`,
  `issue.yml`, `add-to-project.yml` — release notes drafting, build-number
  bumps, and issue/project automation.
- Release channels are build configurations: `Debug`, `Alpha`, `Beta`, `Pre`,
  `Release`, configured via the files in `Configs/` (channel-specific icons and
  version postfixes). The marketing version is set in `CodeEdit/Info.plist`
  (`CFBundleShortVersionString`); build numbers are managed with `agvtool`.

## Security Considerations

- The app is **not sandboxed** (`CodeEdit/CodeEdit.entitlements` only keeps the
  app-scope bookmark and app groups entries). Language server detection and
  launch therefore use the user's login shell environment directly, without
  security-scoped bookmarks. Do not add entitlements without a clear need.
- Release builds are codesigned with the hardened runtime and notarized;
  Sparkle updates are EdDSA-signed. The signing keys live only in CI secrets.
- Secrets for the user are stored in the macOS Keychain via
  `CodeEdit/Utils/KeyChain`. Never commit credentials, certificates, or API
  keys.
- The integrated terminal executes arbitrary shell commands by design; be
  careful when changing `ShellClient`/`TerminalEmulator` code that builds shell
  commands, and never interpolate unsanitized user input into shell strings.

## Contributing Conventions

- Comment on an issue (or get assigned) before starting work — see
  `CONTRIBUTING.md`.
- PRs must fill out the template: descriptive title, detailed description,
  screenshots/video for UI changes, and a linked issue. Resolve all merge
  conflicts and SwiftLint violations; all CI checks must pass.
- Community: Discord server and weekly meetup; links in `README.md`.

## Commands (supplements Build and Test Commands)

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
