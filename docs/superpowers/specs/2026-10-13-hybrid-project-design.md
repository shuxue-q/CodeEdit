# Flutter + C++ + Rust Hybrid Projects — Design

Date: 2026-10-13
Status: implemented on `feat/hybrid-project`
Builds on `2026-10-13-flutter-dart-support-design.md` and `2026-10-13-rust-support-design.md`.

## Problem

CodeEdit now speaks Dart, C++ and Rust, but only CMake has project-level support (presets,
build settings, variables, run target, a build controller that feeds Problems). A Flutter app
that bundles a C++ core and a Rust crate, such as `~/Desktop/OmniExam`, gets a Flutter pane
that shows the SDK and native root, nothing for Cargo, no Flutter or Cargo tasks, and no
Problems from `flutter` or `cargo` output.

OmniExam's configuration files:

| Toolchain | Files |
| --- | --- |
| Flutter / Dart | `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, `.metadata`, `hook/build.dart` (native assets hook that runs CMake), `macos/`, `windows/` runners, `third_party/flutter_math_fork/pubspec.yaml` (path dependency) |
| C++ | `CMakeLists.txt` (root, `add_subdirectory(cpp)`), `CMakePresets.json`, `cpp/CMakeLists.txt` (runs `cargo build` for the Typst kernel), `.clang-format`, `.clang-tidy` |
| Rust | `rust/Cargo.toml` (`[workspace]`, members `omniexam_typst`, release profile), `rust/omniexam_typst/Cargo.toml` (`staticlib` + `rlib`, a `[[bin]]`, examples, tests, `build.rs`), `rust/rust-toolchain.toml` (channel `1.97.1`, three targets) |

## Decisions (agreed 2026-10-13)

1. All three toolchains are parsed and configurable from the project editor.
2. Panes show parsed facts plus a few choices: Flutter device, build mode, target file, flavor,
   `--dart-define`s, extra arguments, hot reload on save, native root; Cargo profile, features,
   target triple, run target, arguments and environment. No large forms beyond that.
3. Flutter and Cargo tasks are generated and run in the task terminal. Hot reload and hot
   restart are supported. No debugging.
4. Both `cargo` and `flutter` output is parsed into Problems.
5. Project-level choices live in `.codeedit/flutter-settings.json` and
   `.codeedit/cargo-settings.json`, next to `cmake-settings.json`. Machine-specific values (a
   Flutter SDK override path) live in `UserDefaults`.
6. Nested packages (`third_party/flutter_math_fork`) are recognized and listed, marked third
   party; tasks and language servers stay on the primary projects.

## Parsing

All parsing reads files only and runs off the main actor. Nothing executes project code.

- **TOML** (`Features/Rust/Models/TOMLDocument.swift`): a small TOML 1.0 reader for Cargo and
  toolchain files: tables, arrays of tables, dotted keys, basic and literal strings (including
  multi-line), integers, floats, booleans, dates kept as strings, arrays (multi-line, nested) and
  inline tables. Errors are reported with a line number and the rest of the file still loads.
- **Cargo manifest** (`CargoManifest`): package metadata (name, version, edition, rust-version,
  description, publish, `build`), workspace (members, exclude, resolver, `workspace.package`
  inheritance markers), `[lib]` (name, crate-type), explicit `[[bin]]`, `[[example]]`, `[[test]]`,
  `[[bench]]`, auto-discovered targets (`src/main.rs`, `src/bin/*.rs`, `examples/*.rs`,
  `tests/*.rs`, `benches/*.rs`, `build.rs`) honouring `autobins`/`autoexamples`/…, features with
  `default`, dependencies of the three kinds (version, path, git, workspace, optional), and
  `[profile.*]` (opt-level, debug, lto, panic, codegen-units, inherits). The old fields keep their
  names, so rust-analyzer's `linkedProjects` discovery is unchanged.
- **Rust toolchain file** (`RustToolchainFile`): `rust-toolchain.toml` (`channel`, `components`,
  `targets`, `profile`) and the legacy one-line `rust-toolchain`.
- **pubspec** (`PubspecParser`): adds description, `publish_to`, environment constraints
  (`sdk`, `flutter`), dependencies / dev_dependencies / dependency_overrides with their source
  (hosted version, `path`, `git`, `sdk`), `flutter.assets`, `flutter.fonts` families,
  `uses-material-design`, `generate`, and plugin platforms with `pluginClass` / `ffiPlugin`.
  Sequences are now read.
- **analysis_options.yaml** (`AnalysisOptions`): `include`, `analyzer.exclude`,
  `analyzer.language` strict modes, `analyzer.errors` overrides, and `linter.rules` in list or map
  form.
- **`.metadata`**: `project_type` and the platforms Flutter generated.
- **Pub state**: whether `.dart_tool/package_config.json` exists and is newer than
  `pubspec.yaml`/`pubspec.lock`; when not, the pane offers `flutter pub get`.

## Project inventory

`ProjectInventory` (`Features/ProjectModel/`) walks the workspace (depth 4; skips hidden
folders, `build`, `target`, `.dart_tool`, `node_modules`, `Pods`, `ephemeral`, `.symlinks`) and
returns components:

| Kind | Found by | Role |
| --- | --- | --- |
| Flutter app / plugin / Dart package | `pubspec.yaml` | primary at the root; `thirdParty` under `third_party/`, `vendor/`, `external/`, `deps/`; `nested` otherwise |
| CMake project | top-most folder with `CMakeLists.txt` (folders below another CMake folder are its subdirectories); Flutter platform runners (`linux/`, `windows/` with `flutter/CMakeLists.txt`) are `platformRunner` | primary for the active native root |
| Cargo workspace / package | `Cargo.toml`; members of a `[workspace]` belong to it | primary unless third party |

It also records links between components, read from text, labelled as detected rather than
certain: a `hook/build.dart` that mentions `cmake` builds the CMake project; a CMake list file
that mentions `cargo` and a Cargo folder name builds that crate; a `pubspec.yaml` path
dependency points at a nested package.

`ProjectInventoryModel` is the workspace-owned `@Observable` wrapper. It reloads when a
configuration file is saved in CodeEdit or changes on disk (the workspace file manager forwards
raw file-system event paths; names are matched against a fixed set and reloads are debounced),
and probes toolchains:

- Flutter: the SDK (existing) or the per-workspace override path.
- Rust, per Cargo root: `rustup show active-toolchain`, installed targets and components for the
  pinned toolchain, run with `RUSTUP_AUTO_INSTALL=0` so a probe never downloads a toolchain.
- CMake: `cmake --version`.
- Language servers: the paths `LSPService` detected for `dart`, `cpp`, `rust`, `cmake`.

When the set of nested Cargo manifests changes, running rust-analyzer servers for the workspace
are restarted so `linkedProjects` follows. A Flutter SDK override also selects the Dart
analysis server binary for that workspace.

## Generated tasks

`ProjectTaskCatalog` turns the inventory and settings into tasks (shell-quoted commands, the
component folder as working directory). They are not written to `.codeedit/settings.json`; the
task manager lists them after the user's own tasks. IDs are stable (derived from the task name),
so the selection survives reloads.

| Component | Tasks |
| --- | --- |
| Flutter (primary) | Run (`flutter run -d <device> --<mode> [-t] [--flavor] [--dart-define…] [args]`), Build (`flutter build <platform> --<mode>`), Test, Analyze, Pub Get, Pub Upgrade, Clean; Build Runner when `build_runner` is a dependency; FFIgen when `ffigen.yaml` exists or `ffigen` is a dev dependency |
| Cargo root | Build, Check, Test, Clippy (`--all-targets`), Doc, one Run per binary and example; profile, features and target from settings |
| CMake | Build (the existing build controller), Test (`ctest --test-dir <build dir> --output-on-failure`) |

The CMake build entry appears only when other generated tasks exist, so a CMake-only workspace
keeps its current Run behaviour (build with no tasks configured).

### Hot reload

- `CEActiveTask` gains `sendInput(_:)`, writing to the task's pseudo-terminal, and an output tap.
- A Flutter Run task is hot-reload capable. The output tap marks it ready when `flutter run`
  prints its key-command help, and reports "Reloaded …"/"Restarted …" in the activity viewer.
- Hot Reload (`⌘\`) sends `r`, Hot Restart (`⇧⌘\`) sends `R`. Both are in the Tasks menu and as a
  bolt button in the run capsule while a capable task is running.
- Saving a `.dart` file inside the Flutter package hot-reloads when `hotReloadOnSave` is on
  (default on), debounced so Save All reloads once.
- Stopping a Flutter Run task sends `q` first (the app quits cleanly), then terminates after
  4 seconds if it is still running.

## Problems from task output

The output tap feeds a per-task parser; results go to `TaskDiagnosticsStore`, which
`WorkspaceDiagnostics.all` merges with CMake and language-server diagnostics, so Problems, the
Issues navigator and the toolbar issue counts all show them. A task's diagnostics are replaced
when it runs again; Clear in Problems clears them too. ANSI escapes are stripped and paths are
resolved against the task's working directory.

- **Cargo** (`CargoOutputParser`): `error[E…]:` / `warning:` headers with their `--> file:line:col`
  line, `thread '…' panicked at file:line:col:` from tests, and unlocated `error:` lines such as
  `could not compile`. Count summaries (`generated N warnings`) are skipped.
- **Flutter** (`FlutterOutputParser`): Dart front-end `file.dart:line:col: Error: …`, analyzer
  bullets (`error • message • file:line:col • code`), Clang/Swift `path:line:col: error: …` from
  Xcode and native-assets builds, `Error (Xcode): …`, and unlocated `Error: …` lines.

## UI

### Project editor sections

Segments depend on what the workspace contains. With two or more toolchains the four CMake
panes collapse into one C++ segment with its own picker; CMake-only workspaces keep the flat
segments they have today.

```
 OmniExam  ·  Flutter + C++ + Rust
 [ Overview | Flutter | Rust | C++ | Version Control | Project Files ]
 ─────────────────────────────────────────────────────────────────────
 C++:   [ Toolchain | Build Settings | CMake Variables | Run / Debug ]
```

### Overview

```
 Components
   ◆ Flutter app      omniexam_app 0.6.0+1        .                      Primary
   ◆ CMake project    omniexam                    .   (native root)      Primary
   ◆ Cargo workspace  omniexam_typst              rust/                  Primary
   ◇ Flutter package  flutter_math_fork           third_party/…          Third party
   ◇ Platform runner  windows                     windows/               Generated
 Connections (detected)
   hook/build.dart builds the CMake project at .
   cpp/CMakeLists.txt builds the Cargo crate rust/omniexam_typst
 Toolchains
   Flutter  3.47.0 · stable · Dart 3.13.0           /Users/…/flutter
   Rust     1.97.1 (rust/rust-toolchain.toml)       ⚠ x86_64-pc-windows-msvc not installed
   CMake    3.31.x
 Language Servers
   Dart ✓  clangd ✓  rust-analyzer ✓  neocmakelsp —
```

### Flutter

```
 Project        name · version · type (.metadata) · description · SDK constraints
 Flutter SDK    path · version · [Rescan]  Override: [ path field ][Choose…][Clear]
 Packages       pub state: ✓ up to date | ⚠ pubspec changed  [Run pub get]
                23 dependencies · 3 dev · path: flutter_math_fork  ▸ All dependencies
 Platforms      macOS ✓  Windows ✓  Linux —  iOS —  Android —  Web —
 Assets         9 asset paths · fonts: XITS Math, …
 Analysis       include: package:flutter_lints/flutter.yaml · 3 excludes · strict-casts …
 Native Code    Active root ( ) Workspace Root ( ) cpp/ … · hook/build.dart (runs CMake)
 Run            Device [macOS ▾][↻] · Mode [Debug|Profile|Release] · Target [lib/main.dart]
                Flavor [ ] · Dart defines (key/value list) · Extra arguments [ ]
                [x] Hot reload on save
```

### Rust

```
 Cargo root [ rust/ ▾ ]            (picker only when several roots exist)
 Workspace      rust/Cargo.toml · resolver 2 · members: omniexam_typst
 Packages       ▸ omniexam_typst 0.1.0 · edition 2024
                   lib (staticlib, rlib) · bin omniexam_typst_cli · 3 examples · 2 tests · build.rs
                   features · dependencies (6 / dev 1 / build 0)
 Toolchain      rust/rust-toolchain.toml → 1.97.1 · active: 1.97.1-aarch64-apple-darwin
                targets ✓ aarch64-apple-darwin ⚠ x86_64-apple-darwin … · components · rust-analyzer ✓
 Build          Profile [dev|release|custom…] (opt-level 0, debug true …) · Target [Host ▾]
                Features [ ] default [x] … · [ ] All features · [ ] No default features
 Run            Target [bin omniexam_typst_cli ▾] · Arguments [ ] · Environment (key/value)
```

### Toolbar

```
 [▶ ■ ⚡]  [ (O) Run omniexam_app  >  macOS · Debug ]
```

The bolt appears only while a hot-reload capable task runs; click reloads, ⌥-click restarts.
The destination segment follows the selected task: Flutter shows device and mode, Cargo the
profile, CMake the configure preset. The popover lists Flutter device and mode, Cargo profile
and CMake presets as applicable, then tasks grouped by component.

### Project Files

The list gains the discovered configuration files, grouped by toolchain, plus
`.codeedit/flutter-settings.json` and `.codeedit/cargo-settings.json`.

## Constraints

- No Liquid Glass; SwiftLint `--strict`; documented public declarations; discovery, probes and
  device listing off the main actor; commands built only from quoted arguments.
- CMake-only, Flutter-only and plain workspaces behave as before apart from the new segments.
- Settings decode leniently (`decodeIfPresent ?? default`); an unreadable file never wipes the
  others.

## Verification

- Unit tests: the TOML reader, Cargo manifests and target discovery, toolchain files, the YAML
  reader, pubspec, analysis options and `.metadata`, the inventory over an OmniExam-shaped
  fixture, the task catalog (commands and quoting), the Cargo and Flutter output parsers
  (including analyzer messages wrapped to the terminal width), the output monitor, settings
  decoding, and the task manager's generated tasks.
- Real terminals and tools: a generated task in a pseudo-terminal receives hot reload (`r`),
  hot restart (`R`) and the graceful stop (`q`); `cargo check` errors and warnings reach the
  problems list through `WorkspaceDocument`; `flutter analyze` issues do too (opt-in with
  `TEST_RUNNER_HYBRID_REAL_FLUTTER=1`).
- The panes are rendered over the fixture by `HybridProjectPaneCaptureTests`
  (`TEST_RUNNER_PANE_CAPTURE_DIR=<folder>`).
- `describesARealWorkspace` (`TEST_RUNNER_HYBRID_WORKSPACE=<folder>`) opens a real project
  read-only and prints its components, links, configuration files, tasks and tool versions.
- `HybridProjectUITests` drives the real app; it needs macOS UI automation to be enabled.
