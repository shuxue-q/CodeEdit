# Flutter projects with native code

CodeEdit recognizes a folder as a Flutter project when its root `pubspec.yaml`
either depends on the Flutter SDK or declares an FFI plugin:

```yaml
dependencies:
  flutter:
    sdk: flutter          # or: flutter: { sdk: flutter }

flutter:
  plugin:
    platforms:
      macos:
        ffiPlugin: true   # any platform with ffiPlugin: true
```

`pubspec.yaml` is read line by line for `name`, `version`, the `flutter`
dependency and `flutter.plugin.platforms.*.ffiPlugin`. Comments, quoted values,
single-line flow mappings and block scalars are handled; anchors and multi-line
flow collections are not. Recognition never runs `flutter`, `dart` or CMake, and
it happens in the background when the workspace opens.

## Flutter SDK

The SDK is the one behind the `flutter` command on your login shell `PATH`.
Symlinks are followed (for example `~/.local/bin/flutter` →
`<sdk>/bin/flutter`), so the SDK root is the folder above that `bin`. The
version comes from `<sdk>/version` or, in recent SDKs that no longer write that
file, from `<sdk>/bin/cache/flutter.version.json` (which also gives the channel
and the Dart version). fvm and other version managers are not consulted. Use
**Rescan** in the Flutter pane after installing or switching SDKs. An **SDK
Folder** chosen in the Flutter pane replaces the `PATH` SDK for that workspace on
this Mac only (it is kept in `UserDefaults`); the generated tasks and the Dart
analysis server then use that SDK.

## Native code and the active root

Native C/C++ code is found as a CMake project. CodeEdit looks for a
`CMakeLists.txt` in these folders, in order:

1. the workspace root,
2. `src/`, `cpp/`, `native/`, `linux/`, `windows/`, `macos/`,
3. `packages/*/src/`, by package name.

The first match is the **active native root**. When several exist, pick another
one in **Project Settings → Flutter → Native Code**; the choice is saved in the
workspace's `.codeedit/flutter-settings.json` (choices made by earlier versions,
kept in `UserDefaults`, are still read) and is dropped automatically if that
folder no longer has a `CMakeLists.txt`.

The active root is the CMake source directory for everything CMake-related:

- the CMake sections of the project editor, Workspace Settings and the scheme
  capsule show its presets;
- builds run there and the preset selection is stored per root;
- clangd gets that root's `compile_commands.json`. An existing database is
  reused — the selected (or first) configure preset's binary directory, the
  root itself, or `<root>/build` — and CMake is configured only when none is
  usable (see [CMake project detection and presets](cmake-project-presets.md)).

Project editor settings stay in the workspace's
`.codeedit/cmake-settings.json`, whichever root is active. Switching the active
root rebuilds the CMake models and restarts clangd with the new database.

C and C++ completion uses the macOS host compile flags of that database. Android
NDK and other cross-compilation toolchains are not set up.

## Recognized layouts

**App with a root CMake project** (for example a `hook/build.dart` that builds
the native core through CMake):

```
my_app/
├── pubspec.yaml          flutter: sdk: flutter
├── CMakeLists.txt        ← active root: add_subdirectory(cpp)
├── CMakePresets.json     macos-debug → build/macos-debug/compile_commands.json
├── cpp/CMakeLists.txt    also listed
├── hook/build.dart
└── lib/
```

**FFI plugin** (`flutter create --template=plugin_ffi`):

```
native_add/
├── pubspec.yaml          flutter.plugin.platforms.*.ffiPlugin: true
├── src/CMakeLists.txt    ← active root (database in src/build)
├── linux/CMakeLists.txt  also listed
├── windows/CMakeLists.txt
└── lib/
```

**Monorepo** with native packages: `packages/<name>/src/CMakeLists.txt`.

## Not covered

Debugging Flutter apps is not part of this support. Running, hot reload, device
selection and the parsed project configuration are described in
[Flutter, C++ and Rust in one workspace](hybrid-projects.md). Dart editing
features come from the Dart language server.
