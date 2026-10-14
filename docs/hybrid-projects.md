# Flutter, C++ and Rust in one workspace

CodeEdit recognizes workspaces that combine a Flutter app, a CMake (C/C++) project and Cargo
(Rust) crates, such as an app whose native core is C++ linking a Rust library. It reads their
configuration files, shows them in the project editor, generates tasks for all three toolchains,
turns the tasks' output into problems, and hot-reloads the running Flutter app.

Everything is read from files. Opening a workspace never runs project code; the only tools
CodeEdit runs on its own are version probes (`flutter devices`, `rustup show`, `cmake --version`).

## What is recognized

The workspace is scanned up to four folders deep. Hidden folders, `build`, `target`,
`node_modules`, `Pods`, `ephemeral`, `DerivedData`, `out` and `CMakeFiles` are skipped.

| Component | Found by | Role |
| --- | --- | --- |
| Flutter app, plugin or package, Dart package | `pubspec.yaml` | Primary at the workspace root, member elsewhere |
| CMake project | `CMakeLists.txt` at the root, or below it in a folder whose list file calls `project()` | Primary at the root, member below a root project |
| Flutter platform runner | `linux/` or `windows/` with `flutter/CMakeLists.txt` next to a pubspec | Generated |
| Cargo workspace or package | `Cargo.toml`; members of a `[workspace]` belong to it | Primary |

Anything under `third_party`, `thirdparty`, `third-party`, `3rdparty`, `vendor`, `external` or
`deps` is third party: listed, never built.

### Configuration files read

| Toolchain | Files | What is shown |
| --- | --- | --- |
| Flutter | `pubspec.yaml` | Name, version, description, SDK constraints, dependencies with their source (hosted, path, git, SDK), dev dependencies, overrides, assets, fonts, plugin platforms |
| | `analysis_options.yaml` | Includes, excludes, strict modes, lint rules, severity overrides |
| | `.metadata` | Project type (app, plugin, FFI plugin, package) |
| | `.dart_tool/package_config.json` | Whether `pub get` is up to date with the pubspec and lock file |
| | `hook/build.dart` | That a native assets hook exists, and whether it runs CMake or Cargo |
| C++ | `CMakeLists.txt`, `CMakePresets.json` | See [CMake project detection and presets](cmake-project-presets.md) |
| Rust | `Cargo.toml` | Package metadata, workspace members (with `*` globs) and resolver, library crate types, binaries, examples, tests, benches and build script (declared and found from the folder layout), features, dependencies of each kind including target-specific ones, profiles |
| | `rust-toolchain.toml`, `rust-toolchain` | The pinned channel, targets and components |

### Build connections

The Overview lists connections found in the build files' text. They are hints, not a build
graph:

- a `hook/build.dart` that mentions `cmake` builds the nearest CMake project;
- a CMake list file that mentions `cargo` and a Cargo folder or package name builds that crate;
- a `path:` dependency in a pubspec points at the package in that folder.

## Project editor

Selecting the workspace root opens the project editor. A workspace with two or more toolchains
gets these sections:

| Section | Contents |
| --- | --- |
| Overview | Components, connections, tool versions (Flutter, Rust per Cargo root, CMake) and the detected language servers |
| Flutter | Project, SDK (with a per-Mac SDK folder override), packages and pub state, platforms, analysis options, native code root and build hook, run settings |
| Rust | Cargo workspace, packages with targets, features and dependencies, pinned toolchain with what rustup has installed, build settings (profile, target, features), run settings (target, arguments, environment) |
| C++ | The CMake Toolchain, Build Settings, CMake Variables and Run / Debug panes behind one picker |
| Version Control, Project Files | As before; Project Files also lists the discovered configuration files, grouped by toolchain |

A workspace with only CMake keeps the four CMake segments at the top level.

### Settings files

| File | Contents |
| --- | --- |
| `.codeedit/flutter-settings.json` | Device, build mode, target file, flavor, `--dart-define`s, extra run arguments, hot reload on save, active native root, build platform |
| `.codeedit/cargo-settings.json` | Per Cargo root (keyed by its folder): profile, features, all features, no default features, target triple, run target, run arguments, environment |

Both files are read leniently: a missing or mistyped key falls back to its default. Edits made
in the project editor are saved half a second later; edits made to the files directly are picked
up when they are saved. The Flutter SDK override is the only machine-specific choice and lives in
`UserDefaults`.

## Tasks

Generated tasks appear in the scheme menu after your own tasks, grouped by component. They are
not written to `.codeedit/settings.json`.

| Component | Tasks |
| --- | --- |
| Flutter app | Run (`flutter --no-wrap run -d <device> --<mode> …`), Build (`flutter --no-wrap build <platform> --<mode> …`) |
| Flutter package | Test, Analyze, Pub Get, Pub Upgrade, Clean; Build Runner when `build_runner` is a dependency; Generate FFI Bindings when `ffigen.yaml` exists or `ffigen` is a dependency |
| Cargo root | Cargo Build, Check (`--all-targets`), Test, Clippy (`--all-targets`), Doc (`--no-deps`), and Run for each binary and example |
| CMake project | Build (the existing CMake build), Test (`ctest --test-dir <build dir> --output-on-failure`) |

Flutter and Cargo settings are applied to every task they concern. Every argument is quoted;
the extra-argument fields are split like a shell would split them first. The CMake entries are
added only next to Flutter or Cargo tasks, so a CMake-only workspace still builds with Run when
no task is configured.

The scheme capsule's destination follows the selected task: a Flutter task shows its device
and build mode, a Cargo task its profile, a CMake task the configure preset. Its menu switches
device, mode and profile.

### Hot reload

While a Flutter Run task in debug mode is running and has printed its key commands:

- the bolt button next to Run and Stop hot-reloads; Option-click hot-restarts;
- **Tasks → Hot Reload** (`⌘\`) and **Tasks → Hot Restart** (`⇧⌘\`) do the same;
- saving a Dart file in the workspace hot-reloads, unless **Hot reload on save** is off.

CodeEdit types `r` or `R` into the task's terminal, exactly as you would; the activity viewer
shows Flutter's "Reloaded …" summary. Stop types `q`, so the app quits cleanly, and terminates
the task if it is still running four seconds later.

## Problems

The output of generated tasks is parsed while they run, and the problems join the CMake build's
and the language servers' in the Problems panel, the Issues navigator and the toolbar counts. A
task's problems are replaced when it runs again; Clear in the Problems panel removes them.

| Tool | Recognized |
| --- | --- |
| Cargo | `error[E…]:` and `warning:` with their `-->` location, test panics with their location, unlocated errors such as `could not compile` |
| Flutter | Dart compiler `file.dart:line:col: Error:`, analyzer `error • … • file:line:col • code`, Clang and Swift messages from Xcode and native assets builds, `Error (Xcode): …`, unlocated `Error: …` |
| CTest | Clang, GCC and Swift `file:line:col: error:` messages |

## Language servers

- **Dart**: the SDK override, when set, also selects the Dart analysis server for the workspace.
- **C++**: clangd uses the active native root's compilation database.
- **Rust**: rust-analyzer gets the Cargo roots below the workspace as `linkedProjects`; when the
  set of roots changes, it restarts.

## Not covered

Debugging Flutter or Rust programs, Android NDK and other cross-compilation setups, and running
`cargo` or CMake to discover more than the files say (no `cargo metadata`, no CMake File API
beyond what the CMake support already uses).
