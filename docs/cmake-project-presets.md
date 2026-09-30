# CMake project detection and presets

Opening a folder with a root `CMakeLists.txt` identifies it as a CMake project.
Open **Workspace Settings…** from the workspace dropdown in the toolbar to see
the **CMake** section. Select a configure preset and, when available, an
associated build preset to inspect compiler settings, build type/configuration,
generator, build directory, and toolchain file.

Selections are stored locally per workspace. Selecting a preset does not edit
the JSON files or execute configure/build commands (see the compilation
database section below for the one place CMake is executed). Files are reloaded
when workspace settings opens; use **Reload** after editing files while it is
open. Discovery and parsing run in the background.

The reader supports configure/build presets in schema versions 1–10, including
`CMakeUserPresets.json`, transitive includes, inheritance (earlier parents win),
hidden presets, conditions, typed cache variables, null overrides, and standard
source/preset/environment macros. Include macros follow their schema's rules.
Only enabled, visible presets are offered. Invalid references, cycles, unsupported
schema versions or macros, and malformed JSON are reported in the CMake section.
This reader extracts settings; it is not a complete CMake JSON schema validator.

Compiler values come from `CMAKE_C_COMPILER` / `CMAKE_CXX_COMPILER`, falling back
to the preset's effective `CC` / `CXX` environment. Single-config presets show
`CMAKE_BUILD_TYPE`; Xcode, Ninja Multi-Config, and Visual Studio presets show the
selected build preset's `configuration`. Unspecified values remain unspecified.
Toolchain files are displayed, but are not executed to infer compiler settings.

Project name, version, and languages are extracted from the root `project()`
declaration, including simple preceding literal `set()` assignments. Comments,
quoted/bracket arguments, and control-flow blocks are recognized. This does not
evaluate CMake scripts or discover targets; dynamic metadata may remain unknown,
and the folder name is used when a project name cannot be resolved statically.

Reference: [CMake presets specification](https://cmake.org/cmake/help/latest/manual/cmake-presets.7.html).

## Project editor

Selecting the workspace root in the project navigator opens a project editor tab
instead of renaming the folder (double-click keeps the tab open). In CMake
workspaces it has four panes, saved to `.codeedit/cmake-settings.json` (created on
the first edit):

- **Toolchain** — C and C++ compilers found in the login shell `PATH`, `/usr/bin`,
  `/opt/homebrew/bin`, `/usr/local/bin`, and the Homebrew LLVM keg, identified from
  `--version` (Apple Clang, Clang, GCC), or a custom path; the detected `cmake` and its
  version; and the generator (Ninja, Ninja Multi-Config, Unix Makefiles, Xcode).
- **Build Settings** — the preset pickers above, the build configuration (`Debug`
  by default), the build directory (`build`), and the C++ standard (17/20/23).
- **CMake Variables** — ordered `-DNAME=VALUE` definitions that can be disabled
  individually, with a preview of the resulting configure command.
- **Run / Debug** — the executable target, working directory, arguments (split with
  shell quoting, never passed through a shell), and environment variables used by
  **Start Debugging** in the Debugger panel.

Without a configure preset, these settings produce the configure step:
`cmake -S <source> -B <build> [-G <generator>] -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
-DCMAKE_BUILD_TYPE=… [-DCMAKE_C_COMPILER=…] [-DCMAKE_CXX_COMPILER=…]
[-DCMAKE_CXX_STANDARD=…] <variables>`. Multi-configuration generators omit
`CMAKE_BUILD_TYPE` and build with `--config`. When a configure preset is selected it
keeps control of the generator, build directory, compilers, build type, and
standard (those controls are disabled); variables are still appended.

Executable targets come from the CMake File API: CodeEdit writes a `codemodel-v2`
query into the build directory before every configure it runs and reads the reply
for each target's binary. Before the first configure, literal `add_executable()`
calls in the project's `CMakeLists.txt` files are listed without binary paths.

## Building and the problems panel

In a CMake workspace without configured tasks, the window's existing start/stop task
controls run the build: pressing ▶ starts `cmake --build` and ⏹ stops it — no separate
build button is added. Workspaces with configured tasks keep the classic task behavior;
programmatic triggers can call `WorkspaceDocument.cmakeBuildController.start()`.

The build runs with piped output (no pseudo-terminal) and is assembled from the workspace
settings selection:

- a selected build preset runs `cmake --build --preset <name>`;
- otherwise `cmake --build <binaryDir>` for the selected configure preset's binary
  directory, or `<source>/build` when no preset is selected;
- when the build directory has no `CMakeCache.txt`, or the cache was created for a
  different source or build directory, a configure step
  (`cmake --preset <name>` or `cmake -S <source> -B <build>` with
  `CMAKE_EXPORT_COMPILE_COMMANDS=ON` and the project editor's settings) runs first.
  A leftover cache from another tree is discarded (`CMakeCache.txt`, `CMakeFiles/`,
  and `compile_commands.json`) before that configure;
- after a successful configure the arguments are recorded in
  `CMakeFiles/codeedit-configure.json`. The next build configures again when they
  differ, and starts from a fresh cache when the requested generator differs from
  the cached `CMAKE_GENERATOR`. Directories without that record are built as they
  are when no project settings exist.

While the build runs, output is parsed incrementally for compiler diagnostics — Clang and
GCC (`path:line:col: warning|error: message`, including `fatal error` and trailing
`[-Wcode]` flags), MSVC (`path(line,col): warning C4996: message`), tool-level messages
(`clang: error: linker command failed …`), CMake errors and warnings (including deprecation
and dev warnings, and `at file:line (command):` blocks), Ninja `FAILED:` edges, and
`make: *** Error` lines. Notes attach to the diagnostic they follow; progress and
source-snippet lines are ignored.

Diagnostics land in the **Problems** tab of the utility area (bottom panel), grouped by
file and ordered by severity, with error/warning counts in the panel toolbar. Clicking an
entry opens the file at the reported line and column. A failed build reveals the Problems
tab automatically. Diagnostics are capped per build; the panel's trash button clears them.
Diagnostics published by running language servers (for example clangd) are merged into the
same list, for CMake and non-CMake workspaces alike.

## Compilation database for clangd

When a C, C++, or Objective-C file is opened in a CMake workspace, CodeEdit
ensures a compilation database exists before starting clangd. When a configure
preset is selected, its binary directory takes precedence; otherwise an existing
`compile_commands.json` in the source directory or `build/` is reused. Otherwise
CMake is configured once — `cmake --preset <name>` when a configure preset is
selected, or `cmake -S <source> -B build` — with
`CMAKE_EXPORT_COMPILE_COMMANDS=ON`, and clangd is launched with
`--compile-commands-dir` pointing at the result. This gives completion,
diagnostics, and semantic highlighting the project's real compile flags.
Generation is skipped when CMake is not installed, when the configure fails
(clangd then runs without a database, or with a pre-existing one as a fallback),
or when the clangd launch arguments already contain `--compile-commands-dir`.
Versioned clangd binaries (`clangd-18`, `clangd-mp-19`, …) are treated the same
as `clangd`.

Selecting a different configure preset, or saving project editor settings that
change the configure step, drops the cached database lookup and restarts the
C-family language servers, so subsequent completion and diagnostics use the new
compile flags. The database uses the same build directory and arguments as
builds, and is regenerated when the recorded configure arguments differ.
