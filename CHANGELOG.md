# Changelog

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
