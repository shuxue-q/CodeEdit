# Rust Language Support — Design

Date: 2026-10-13
Status: implemented on `feat/rust-support`.
Builds on `2026-10-13-flutter-dart-support-design.md` (the Dart work is the template),
`2026-10-09-smart-completion-engine-design.md` and `2026-09-28-completion-aggregator-design.md`.

## Problem

CodeEdit highlights Rust (the vendored `tree-sitter-rust` grammar) and maps `.rs` files to the LSP
language id `rust`, but no Rust language server is ever started: `LanguageServerDetector` knows
`clangd`, `neocmakelsp` and `dart` only. Rust files get no completion, diagnostics or hover, and the
intent recognizer weights every candidate with the flat 0.5 of `.unknown`. Mixed repositories (the
sample `~/Desktop/OmniExam`: Flutter app at the root, Cargo workspace in `rust/`) keep `Cargo.toml`
below the workspace root, where `rust-analyzer` does not look on its own.

## What rust-analyzer offers

Probed with `rust-analyzer 1.97.1` (rustup component) on OmniExam's `rust/omniexam_typst`:

- Completion trigger characters `:` `.` `'` `(`; `resolveProvider: true`,
  `labelDetailsSupport: true`. **Every** list is `isIncomplete: true` (warm answers take 10–40 ms).
  Items carry no `detail`: the signature is in `labelDetails.description`, and an item from a
  module the file does not import has `labelDetails.detail = "(use std::collections::HashMap)"`.
  The `use` edit arrives only from `completionItem/resolve` (`additionalTextEdits`), because
  CodeEdit lists `additionalTextEdits` in `resolveSupport.properties`.
- Callables are snippets (`fmt(${1:f})$0`, `font_count()$0`) with
  `completion.callable.snippets = "fill_arguments"`. Server-side postfix snippets (`.ref`, `.if`,
  `.match`, kind `Snippet`) arrive after `.`, with `additionalTextEdits` that rewrite the receiver.
- Requests to the client: `window/workDoneProgress/create` once per progress token (Fetching,
  Building CrateGraph, Roots Scanned, Loading proc-macros, Indexing, `cargo check`), and
  `workspace/diagnostic/refresh`. `workspace/configuration` is requested only after
  `workspace/didChangeConfiguration`, not at startup, so initialization options carry the settings.
  `experimental/serverStatus` is sent only to clients that advertise it; CodeEdit does not.
- Flycheck (`cargo check`) runs once after the workspace loads and then on `textDocument/didSave`.
  CodeEdit never sent `didSave` before this change.
- The proxy `~/.cargo/bin/rust-analyzer` is a symlink to `rustup`. It exists even when the
  component is not installed, and it honours a project's `rust-toolchain.toml`: OmniExam pins
  `1.97.1`, a toolchain without the component, so the proxy fails inside that project even after
  `rustup component add rust-analyzer` for the default toolchain. `std` completion also needs the
  project toolchain's `rust-src` component.

## Decisions

- Detection (off the main actor, login-shell environment): when `rustup` is on the `PATH`, launch
  the real binary from `rustup which rust-analyzer` (the default toolchain's, like Dart's bundled SDK
  binary), so a project's pinned toolchain cannot break the launch. Otherwise use `rust-analyzer`
  on the `PATH` if `rust-analyzer --version` exits 0. A non-zero exit means "not found"; the LSP
  settings row then hints `rustup component add rust-analyzer`.
- Workspace roots: a root `Cargo.toml` needs nothing. Otherwise discover nested manifests (depth
  ≤ 3, skipping `target/`, `build/`, `.dart_tool/`, `node_modules/`, hidden directories and
  symlinks) and pass them as `initializationOptions.linkedProjects`. A `[workspace]` manifest
  covers manifests below its directory (except paths its `exclude` lists), so members are not linked
  twice. No project pane: unlike Flutter's single native root there is no choice to make or persist,
  all discovered projects are linked. Discovery lives in `Features/Rust/` with unit tests.
- Initialization options (also the answer to `workspace/configuration` section `rust-analyzer`):
  `checkOnSave: true`, `check.command: "check"`, `completion.callable.snippets: "fill_arguments"`,
  `files.watcher: "server"` (CodeEdit sends no `didChangeWatchedFiles`), plus `linkedProjects`.
- Protocol: for `rust`, answer `window/workDoneProgress/create` with success; `$/progress` is
  decoded and dropped quietly; unknown requests (`workspace/diagnostic/refresh`) keep the
  method-not-found reply. Other servers keep their current (unanswered) behaviour.
- `textDocument/didSave` after a document is saved (including autosave), for `rust` only, so flycheck
  diagnostics follow edits. Other servers keep their current behaviour.
- Completion plumbing: `rust` joins `LSPCompletionProvider.incompleteListLanguageIds` (re-request
  while typing, `labelDetails` fill the empty `detail`). Resolve-on-accept already inserts the `use`.
- Out of scope: Cargo run/test tasks, debugging Rust through `lldb-dap`, inlay hints, rust-analyzer's
  custom semantic token types (unmapped types keep the tree-sitter highlight).

## Intents

`RustLineScanner` hands code to the shared `CompletionLineScanner` (new `.rust` dialect with `::`,
`->`, `=>`, `..`, `..=`, `::<`, `&&`, `||`, `?`), after reading strings (`"…"`, `r"…"`,
`r#"…"#`, `b"…"`, `br"…"`, `c"…"`), char literals versus lifetimes (`'a'` vs `'a`), `//` `///` `//!`
comments and nested `/* /* */ */` block comments. `RustTokenRules` + `RustKeywords` decide:

| Site | Example | Intent |
| --- | --- | --- |
| Member access | `self.`, `x?.`, `v.iter().` | `.memberAccess` |
| Path | `std::`, `Self::`, `crate::io::` | `.scopeAccess` |
| `use` path | `use `, `use std::{`, `use std::{fs, ` | `.scopeAccess` |
| New name | `let `, `let mut `, `fn `, `struct `, `enum `, `trait `, `mod `, `const `, `static `, `type `, `for ` (loop pattern), `fn f(`, `fn f(a: u8, `, `|` (closure parameters) | `.declarationName` |
| Type | `let x: `, `fn f(a: `, `-> `, `impl `, `impl<T> `, `impl A for `, `dyn `, `as `, `where `, `T: `, `Vec<`, `::<`, `fn f(x: &`, `&mut ` after a type colon, `&'` | `.typeName` |
| Value | `= `, `return `, `=> `, `f(`, `f(a, `, `if `, `while `, `match `, `in `, `if let `, `&` in an expression, operators | `.expression` |
| Macro call | `println!(`, `vec![`, `format!("{}", ` | `.expression` |
| Attribute | `#[`, `#![`, `#[derive(`, `#[cfg(test)]` before it closes | `.preprocessor` |
| Struct literal field | `Point { x: ` | `.expression` |
| Statement start | a new line in a `fn` body or block | `.statement` |
| Item scope | file scope, `impl`/`trait`/`mod` bodies | `.topLevel` |
| Struct or enum body | a new line in `struct S { … }` / `enum E { … }` | `.declarationName` |
| String, comment, number | `"…`, `r#"…`, `b'…`, `//`, `///`, `/* /* */`, `42` | `.string` / `.comment` / `.numberLiteral` |

Attributes map to `.preprocessor`: they are Rust's compile-time directives, as the preprocessor is
C's; the policy there admits the server's items (attribute names and derive macros arrive as
functions and modules) and macros, and excludes keywords and statement snippets. `if let `/`while let `
are `.expression` because the pattern is usually a variant (`Some(`, `Ok(`), not a fresh name.

Policy: Rust needs no new weights. The generic rules already allow keywords and snippets at
`.statement`/`.topLevel`, and exclude local snippets and keywords after `.` and `::`;
server postfix snippets after `.` weigh 0.4, below members.

Tables: keywords by position (statement keywords, item keywords at file/impl scope, value keywords
`true` `false` `self` `Self` `None` `Some` `Ok` `Err`, type keywords `dyn` `impl` `mut`); snippets
`fn`, `impl`, `struct`, `enum`, `trait`, `match`, `if let`, `while let`, `loop`, `for`, `main`,
`test`, `derive`, `mod tests` with four-space indentation.

## Verification

Unit tests: detector resolution (fake rustup/proxy scripts), discovery layouts, manifest parsing,
scanner, every table row, policy, snippet tables, configuration answers; existing C, CMake and Dart
tests unchanged. Integration tests against the real server (skipped without `rust-analyzer`):
`self.` members, `std::` paths, an unimported type gets its `use` on accept, hover, `cargo check`
diagnostics after save. App check: open OmniExam, open `rust/omniexam_typst/src/lib.rs`, confirm the
linked project, completion, hover, and a responsive editor while indexing.

## Constraints

No Liquid Glass, no new dependencies, SwiftLint `--strict` clean, public declarations documented,
detection and discovery off the main actor, C/C++/CMake/Dart behaviour unchanged.
