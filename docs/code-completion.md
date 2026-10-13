# Code completion

CodeEdit's completion popup gathers candidates from several sources, ranks them by what you are
most likely writing at the cursor, and does the follow-up work when you accept one (an `#include`,
the call parentheses, parameter hints). It is built for C and C++ with `clangd`; CMake, Dart and Rust have rules of their own (see their
sections below), and other languages keep working through their language server, snippets and document words,
but get none of the C-family heuristics described below.

Everything here runs locally except the opt-in [AI completions](#ai-completions).

## Opening the popup

| How | What happens |
| --- | --- |
| Type | The popup opens as you type a name and after the language server's trigger characters (for `clangd`: `.`, `->`, `::`). |
| `⌃Space` | Opens the popup on request, also where typing would not (see below). |
| `⌃⇧Space` | [Chain completion](#chain-completion). |

Typing does not open the popup inside comments, strings and number literals, or while you are naming
a new declaration (`int |`, `std::string |`), where a list only gets in the way. `⌃Space` always opens
it; in those places it offers everything at a low weight.

## What the popup offers

Each row has a trailing badge that says where it came from.

| Badge | Source | What it offers |
| --- | --- | --- |
| Language server | The language server (`clangd` for C and C++) | Symbols, members, headers, macros. |
| Snippet | CodeEdit's tree-sitter tables | Statement and declaration templates such as `for` or `while`. |
| Keyword | CodeEdit's tree-sitter tables | Language keywords. |
| Postfix | [Postfix templates](#postfix-templates) | `expr.if`, `expr.fori`, … after a `.`. |
| Word | [Document words](#document-words) | Identifiers already in the file. |
| AI suggestion | The [AI provider](#ai-completions) | Up to three model suggestions. |

When two sources offer the same name, the higher source wins: language server, snippet, postfix,
keyword, AI, word.

## How the list is ordered

The ranker adds up several signals per candidate, and sorts by the total.

- **Intent.** CodeEdit recognizes what you are writing from the text before the cursor and the syntax
  tree: a member (`.`, `->`), a scoped name (`::`), a header path, a preprocessor line, a type, the name
  of a new declaration, a `case` label, an expression, a statement, a top-level declaration, a comment,
  a string, or a number. Each intent decides which kinds of candidates are allowed and how much they
  weigh. After `.` methods and fields lead, in a `case` label enumerators do, after `const` types do.
  Snippets and keywords never appear after `.`, `->`, `::`, in `case` labels or in an `#include`.
- **Match quality.** A fuzzy match of what you typed, with a bonus for the right case and for
  candidates whose kind fits the shape of the prefix (`ALL_CAPS` looks for a macro, `Capitalized` for a
  type).
- **The server's opinion.** `clangd` sends a relevance score with each item; it is used as it is. For
  servers that send none, the order of their `sortText` stands in for it.
- **Frequency and recency.** CodeEdit remembers what you accept, per language and intent (and, after a
  `.`, per type of the object). Items you accepted often rank higher, and items you accepted a moment ago
  more so; the recency bonus fades over about 30 minutes.
- **Proximity.** A name that already occurs in the current file gets a bonus, so the symbols you are
  working with float up.
- **Expected type.** Where the code expects a value of a known type, candidates of that type get a strong
  bonus and candidates convertible to it a smaller one. Other types are never pushed down.

The first row is **preselected** (shown in bold) only when it clearly stands out: the server marked it
preselected, its total beats the runner-up's by a margin, or it alone starts with exactly what you typed.
Otherwise nothing is preselected and the first row is just the first row.

AI suggestions are placed after the first two other rows, so they never bury an exact match.

### Expected type

The expected type is worked out from the text before what you are typing. It is used only in C and
C++ (including Objective-C).

| Before the cursor | Expected type | Needs the language server |
| --- | --- | --- |
| `T x =` | `T` | No |
| `x =` | The type of `x` | Yes (hover) |
| `return` | The return type of the enclosing function | No |
| `f(`, `f(a,` | The type of the parameter at the cursor | Yes (signature help) |
| `if (`, `while (`, `!`, `&&`, `\|\|` | `bool` | No |
| `case` | The type of the `switch` condition | Yes (hover) |
| `T{`, `T(` | `T`, when `T` is a type name and no signature is known | No |

`return` reads the function's declaration from the syntax tree. While you type, the tree often has no
function around the cursor yet, so CodeEdit then reads the text instead: everything in front of the
function's name, without `static`, `inline`, `virtual`, `constexpr`, `extern` and `explicit`, with the
pointer stars kept. A `void` function, a constructor, an `auto` return type, a trailing return type
(`auto f() -> int`) and a lambda body give no expected type rather than a wrong one.

Requests to the language server for the expected type are limited to 200 ms per keystroke and cached, so
a slow server costs the type bonus, never the popup.

## Accepting an item

- **Automatic includes.** Accepting a symbol that needs a header applies the extra edit the language
  server attaches to it, usually an `#include`. `clangd` does this when its header insertion is on, which
  it is by default. If an item has no extra edit yet and the server can resolve items, CodeEdit asks for
  it, waiting at most 300 ms. The whole acceptance is one undo step. Setting: **Apply Additional
  Completion Edits**.
- **Call parentheses and parameter hints.** Accepting a function or method adds `()` unless one follows
  already. The caret goes between the parentheses when the function takes parameters (or its signature
  cannot be read) and after them when it takes none, and the parameter hints open. Items whose text
  already contains parentheses, such as `clangd`'s snippets with argument placeholders, are inserted as
  they are. Setting: **Insert Parentheses for
  Functions**.
- **Commit characters.** With a row highlighted, typing `(`, `.`, `;`, `,`, `)` or `[` accepts it and
  then inserts the character; a server can send its own set. It only applies when you have typed at
  least one character, so `obj.` followed by `(` never accepts the first member, and it does not apply to
  snippets, keywords, AI suggestions, words or file paths. When what you typed is exactly the name of
  another row (`i.` with a variable `i`), nothing commits. Accepting with `(` or `[` does not add
  parentheses of its own. Setting: **Accept Completions with Commit Characters**.

The three settings are on the **Text Editing** page of the settings window and are on by default.

## CMake files

`CMakeLists.txt` and `*.cmake` files get their own intent rules and tables (the language server is
`neocmakelsp`). CodeEdit recognizes three places in a CMake file:

- **A command name**, the first word of a line (`add_|`). The popup lists commands first, then
  snippets such as `add_executable`, `if`, `foreach`, `function`, `option`, `find_package`,
  `install(TARGETS …)` and `add_custom_command`, which insert placeholders you tab through.
- **An argument**, after the `(` or a space (`target_link_libraries(app PU|`). An `ALL_CAPS` prefix
  looks for a keyword argument, so `PU` offers `PUBLIC` first. Targets, variables, modules and
  paths from the server follow.
- **A variable name** inside `${…}`, `$ENV{…}` or `$CACHE{…}`, also inside quoted text. Only
  variables are offered there.

Typing does not open the popup inside `#` comments (or `#[[ … ]]`) and inside quoted or bracket
arguments, except after a `${`, since CMake expands variables inside quotes. Paths and versions
(`src/main.cpp`, `3.20`) are plain arguments, so the popup stays available.

## Dart files

`.dart` files are served by the Dart analysis server (`dart language-server`). CodeEdit uses the Dart
SDK of the `flutter` on your login shell `PATH` (`<flutter>/bin/cache/dart-sdk/bin/dart`), or `dart` on
the `PATH` when there is no Flutter SDK; the **Language Servers** settings page shows the path and lets
you pick another binary. The server analyzes only the packages that have open files and reports
problems for open files only.

- The popup offers symbols from libraries the file does not import yet. When such a row is
  highlighted, its detail reads *Auto import from '…'*, and accepting it adds the `import`: the server
  supplies the edit when the item is resolved, under the same **Apply Additional Completion Edits**
  setting as `#include`s.
- A request returns at most 500 items (the server's own default is 2000, about 1 MB for a one-letter
  prefix in a Flutter project, which misses the language server's 150 ms window). The server filters
  them by what you typed. A list cut off at 500 is marked incomplete, so while the popup is open each
  further character asks the server again; the popup keeps filtering the previous list until the new
  answer replaces the server's rows. C, C++ and CMake keep filtering their first list.
- A row shows the server's label details (the signature, and for a library not imported yet the
  library, such as `dart:typed_data`) when the server sends no other detail.

### Dart intents

Dart has intent rules of its own, read from the line before the cursor first and from the syntax tree
when the line is inconclusive (a new line of a multi-line argument list, a new statement). They decide
what is offered and how it is ordered, as for C:

| Where | Example | What leads |
| --- | --- | --- |
| Member access | `context.`, `a?.`, `b..`, `b?..` | Members; no snippets or keywords. |
| Type position | `new `, `is `, `is! `, `as `, `extends `, `implements `, `with `, `on `, `List<`, a parameter list | Types, then `required`, `this`, `super`. |
| New declaration name | `var `, `final `, `const `, `late `, `Widget `, `String? `, `List<int> ` | Typing stays quiet (`⌃Space` still works). |
| Call arguments | `Text(`, `Padding(padding: x, `, a new line inside `Padding(…)` | The named arguments the call still accepts (`child: `, `padding: `), then values; no snippets. |
| Value | `child: `, `= `, `return `, `=> `, `?? ` | Values and constructors; no snippets. |
| Statement start | a new line in a function or closure body | Statement keywords and snippets, then values. |
| File or class scope | `cl` at the top of a file or in a class body | Declaration keywords and snippets, then types. |
| Interpolation | `'Hi $na`, `'Hi ${us` | Variables, then getters and functions; no keywords or snippets. |
| Directive URI | `import 'package:fl` | Libraries and files from the server. |
| String, comment, number | `'…`, `//`, `///`, `/* … */`, `42` | Typing stays quiet. |

`const ` starts a declaration only where a statement or member can start (`const x = 1;`); after a
named argument, `return`, `(` or `[`, or on a new line of a widget list, it introduces a constant
constructor call (`child: const Text(…)`), a type position. Code inside `${…}` follows the rules
above (`'${user.` is member access), and a bare `$` in a raw string (`r'…'`) or after a backslash
(`'\$'`) is text. `$` starts the interpolated name, so `'Hi $na` completes `na`.

The keyword and snippet tables offer, where they fit:

- **Snippets** at file or class scope: `stless` (a `StatelessWidget`), `stful` (a `StatefulWidget` and
  its `State`), `build` (an `@override` of `build`), and `main`. At statement start: `for`, `forin`,
  `if`, `switch`, and `try`. Mirrored placeholders change together, such as the widget name in `stless`.
- **Keywords**: statement keywords (`if`, `return`, `try`, `yield`) at statement start; `var`, `final`,
  `late`, `const`, `void` and `dynamic` where a statement or member starts; `import`, `class`, `mixin`,
  `extension`, `static`, `factory` and the class modifiers at file or class scope; `true`, `false`,
  `null`, `this`, `super`, `const` and `await` where a value goes, including call arguments; `required`
  and `covariant` in parameter lists. Types such as `int` and `String` come from the server.

## Rust files

`.rs` files are served by `rust-analyzer`. With rustup, CodeEdit launches the real binary of your default
toolchain (`rustup which rust-analyzer`), not the `~/.cargo/bin/rust-analyzer` proxy: the proxy exists even
when the component is missing, and inside a project whose `rust-toolchain.toml` pins a toolchain without the
component it fails to start. Without rustup, `rust-analyzer` on your login shell `PATH` is used if
`rust-analyzer --version` runs. When neither works, the **Language Servers** settings row says **Not Found**
and shows how to install it: `rustup component add rust-analyzer`. Completion of `std` also needs the
`rust-src` component of the toolchain the project builds with (`rustup component add rust-src`).

- **Cargo projects below the folder.** rust-analyzer finds a `Cargo.toml` at the root of the opened folder
  by itself. When there is none (a Flutter app with its crates in `rust/`, for example), CodeEdit looks for
  `Cargo.toml` files up to three folders deep and hands them to the server as linked projects. It skips
  `target/`, `build/`, `.dart_tool/`, `node_modules/`, hidden folders and symbolic links, and a manifest with
  a `[workspace]` table stands for the crates below it (except those in its `exclude` list). Nothing is
  run to find them, and nothing is stored: the search runs again when the server starts.
- **Checks.** The server runs `cargo check` after loading the project and each time you save a Rust file
  (autosave included), and its errors and warnings join the problems list next to its own.
- **Unimported items.** The popup offers types and functions from modules the file does not import yet;
  their row reads `(use std::collections::HashMap)`, and accepting one adds the `use` line (the server
  supplies it when the item is resolved, under **Apply Additional Completion Edits**).
- **Calls.** Functions and methods are inserted with their parameter names filled in as tab stops:
  accepting `increment(…)` writes `increment(by)`.
- Every list rust-analyzer sends is marked incomplete, so while the popup is open each character asks the
  server again, as for Dart. Rows show the server's label details (the signature, and the `use` an item
  would add), since rust-analyzer sends no other detail.
- While rust-analyzer indexes a project for the first time, completion and hover answer with what it has
  loaded so far; the editor stays responsive. Its progress reports are accepted and not shown.

### Rust intents

Rust has intent rules of its own, read from the line before the cursor first and from the syntax tree when
the line is inconclusive (a new line):

| Where | Example | What leads |
| --- | --- | --- |
| Member access | `self.`, `x?.`, `v.iter().` | Fields and methods; rust-analyzer's own postfix templates (`.ref`, `.match`) after them; no snippets or keywords. |
| Path | `std::`, `Self::`, `crate::io::`, anywhere in a `use` | Modules and types first; no snippets or keywords. |
| New name | `let `, `let mut `, `fn `, `struct `, `enum `, `trait `, `mod `, `const `, `static `, `type `, `for `, a parameter list, a closure's `\|` | Typing stays quiet (`⌃Space` still works). |
| Type | `let x: `, `fn f(a: `, `-> `, `impl `, `dyn `, `as `, `where `, `T: `, `Vec<`, `::<`, `&` or `&mut ` there, `&'` | Types, then `dyn`, `impl`, `mut`, `Self`. |
| Value | `= `, `return `, `=> `, `f(`, `f(a, `, `if `, `while `, `match `, `in `, `if let `, `Point { x: `, a macro's `(` or `[` | Values; no snippets. |
| Attribute | `#[`, `#![`, `#[derive(` | The server's attributes and derive macros. |
| Statement start | a new line in a function body or block | Statement keywords and snippets, then values. |
| Item scope | file scope, `impl`, `trait` and `mod` bodies | Item keywords and snippets, then types. |
| Struct or enum body | a new line in `struct S { … }` | Typing stays quiet: a field or variant name goes there. |
| String, comment, number | `"…`, `r#"…`, `b'…`, `//`, `///`, `//!`, `/* /* */`, `42` | Typing stays quiet. |

`if let ` and `while let ` are values because the pattern is usually a variant (`Some(`, `Ok(`). `'a`
after `&`, `<` or `:` is a lifetime, and `'a'` a character.

The keyword and snippet tables offer, where they fit:

- **Snippets** at file scope and in `impl`, `trait` and `mod` bodies: `fn`, `impl`, `struct`, `enum`,
  `trait`, `main`, `test` (a `#[test]` function), `derive` (`#[derive(Debug)]`) and `mod tests` (a
  `#[cfg(test)]` module with `use super::*;`). At statement start: `match`, `if let`, `while let`, `loop`,
  `for` and `fn`.
- **Keywords**: `let`, `while`, `for`, `return`, `break`, `continue` and `else` at statement start; `if`,
  `match` and `loop` there and where a value goes; item keywords (`fn`, `struct`, `impl`, `use`, `const`,
  `unsafe`, `async`) wherever an item can start, and `mod`, `pub`, `extern`, `union`, `macro_rules!` at item
  scope; `true`, `false`, `self`, `Self`, `None`, `Some`, `Ok`, `Err` and `move` where a value goes; `dyn`,
  `impl`, `mut` and `Self` in a type. Primitive and library types come from the server.

## Document words

When there is no better source (the language server is not installed, still starting, or slow), the
popup offers identifiers that already occur in the file, with the **Word** badge. They are offered from
two typed characters on (or on `⌃Space`), only where a plain name makes sense (an expression, a
statement, a top-level declaration, a type position), they have to be at least three characters long, and
they always weigh less than a real symbol. The word you are typing is not offered unless it also occurs
elsewhere.

## Postfix templates

After a `.` in C and C++, the popup also offers templates that rewrite the expression in front of the
dot. Accepting `items.for` replaces the whole `items.for` and leaves a snippet with tab stops. Only `.`
triggers them, not `->` or `::`. A template typed out in full (`.if`) ranks above members that merely
contain those letters; a partly typed one stays below the members. `expr` is the expression before the
dot, `name` and `T` are tab stops.

| Template | C++ expansion | Notes |
| --- | --- | --- |
| `if` | `if (expr) { … }` | |
| `else` | `if (!(expr)) { … }` | |
| `not` | `!expr` | `!(expr)` unless `expr` is a name, member chain or call |
| `while` | `while (expr) { … }` | |
| `for` | `for (const auto &item : expr) { … }` | C++ only |
| `fori` | `for (size_t i = 0; i < expr; ++i) { … }` | type and index name are tab stops |
| `forr` | `for (size_t i = expr - 1; i >= 0; --i) { … }` | |
| `return` | `return expr;` | |
| `var` | `auto name = expr;` | C: `int name = expr;` |
| `new` | `new expr()` | C++ only, when `expr` is a type name |
| `par` | `(expr)` | |
| `cast` | `static_cast<T>(expr)` | C: `(T)expr` |
| `switch` | `switch (expr) { case …: }` | |
| `nn` | `if (expr != nullptr) { … }` | C: `NULL` |

## Chain completion

Press `⌃⇧Space` where a value of a known type is expected, for example after `std::string label = `.
CodeEdit looks at the best few symbols in scope (up to eight variables and getters whose type has
members), asks the language server what follows `symbol.` in a scratch copy of the file, and offers the
members whose type fits, such as `car.label`. Accepting one inserts the whole chain. Your file is never
edited for this: the scratch copy is a second, temporary document on the language server, closed again
when the document is. If no chain is found in time, or nothing is expected at the cursor, the regular
list is shown.

## Latency budget

The popup must open or update within 500 ms of a keystroke and never later than 1 s. To keep to that:

- Snippets, keywords, postfix templates and words are answered locally and are always included.
- The language server has 800 ms. A fast server (150 ms) is included in the first list; a slower one is
  waited for only if there is nothing else to show. Its late answer is merged into the list on the next
  cursor move.
- The AI provider has 2.5 s of its own, but is only waited for when nothing else could be offered, and
  never beyond one second after the keystroke: the language server and AI share that one second, so AI
  gets whatever the server left of it. A later AI answer is merged on a later cursor move.
- Expected-type lookups have 200 ms; chain completion has 800 ms in total.

## AI completions

AI completions are **off by default**. Turn them on under **Settings › Text Editing › AI Completions**.
They add up to three suggestions with the AI badge. While they are off, or no key is set, nothing is sent.

| Provider | Endpoint | Default model | Key |
| --- | --- | --- | --- |
| Anthropic | Anthropic's Messages API | `claude-opus-5` | Required |
| OpenAI | OpenAI's Chat Completions API | `gpt-5` | Required |
| OpenAI-compatible | The **Base URL** you set | none | Required, except for a server on this Mac |

The OpenAI-compatible provider serves any server that implements the Chat Completions API. The
**Presets** menu fills in the base URL (and a model, where there is a sensible one) for Ollama
(`http://localhost:11434/v1`), LM Studio (`http://localhost:1234/v1`), DeepSeek, Moonshot and Qwen
(DashScope). A server at `localhost`, `127.0.0.1` or `::1` needs no key and gets no `Authorization`
header.

**Keys.** Each provider has its own entry in the macOS Keychain, so a key is only ever sent to the
provider it was entered for. Keys are never written to `settings.json`.

**Test Connection** sends one tiny request (a sample `int main() { ret`, not your code) with a five-second
limit, and reports "Reached *model* in *n* ms" or the server's own error, for example
"404 Not Found: model 'x' not found". It always sends, even when completion is paused after a failure
(below), and a success ends that pause.

**What is sent, and when.** After you type two characters of a name (or press `⌃Space`), and the window
is not paused, one request goes to the selected provider. A newer keystroke cancels the previous request.
It contains:

- the language, a short description of what you are typing, and the typed prefix;
- up to 4,000 characters before the cursor and 1,000 after it, from the current file only;
- when they are known, the expected type, the type of the object before the cursor, and the header of
  the enclosing function (at most 600 characters in all);
- your API key, as the provider expects it.

No other files, project paths or settings are sent. Models are asked for at most three short suggestions.

**When a request fails.** The popup is never held up and the failure is not shown, but the provider
backs off instead of failing on every keystroke:

| Server answer | Paused for |
| --- | --- |
| 429, 529, 5xx (rate limit, overload, server error) | 30 seconds |
| 401, 403 (key rejected) | 5 minutes |
| 400, 404, 422 (request refused: wrong model name or base URL) | 2 minutes |
| Network unreachable or timed out | 60 seconds |

Changing the provider, model, base URL or key ends the pause at once. The 2-minute pause is logged once,
with the provider and the server's message. OpenAI's current models reject `max_tokens` and any
`temperature`, so the **OpenAI** provider sends `max_completion_tokens` and no `temperature`, and the
**OpenAI-compatible** provider sends `max_tokens` and `temperature: 0.2`. If a server answers 400 and names
one of those parameters, the request is repeated once with the other wording, and the wording that works
is used from then on, until the configuration changes. The **OpenAI** provider allows 1024 output tokens
because OpenAI counts a reasoning model's hidden reasoning against the limit; the **OpenAI-compatible**
provider allows 256.

## Local data

All of this stays on your Mac, in `~/Library/Application Support/CodeEdit/`.

| File | Content |
| --- | --- |
| `completion-frequency.json` | How often you accepted each name, per language. |
| `completion-statistics.json` | The same per intent, per receiver type, and when each was last accepted. |
| `completion-metrics.json` | The last 30 app sessions: popups opened, items accepted, the average row of accepted items, keystrokes between popup and accept, and the median and 95th-percentile response time of each provider (and of each AI backend). |

Delete a file to reset what it holds. Nothing in them is sent anywhere.

## Settings reference

| Setting (**Text Editing** page) | Key in `settings.json` (`textEditing`) | Default |
| --- | --- | --- |
| Apply Additional Completion Edits | `completion.applyAdditionalEdits` | on |
| Insert Parentheses for Functions | `completion.insertParenthesesForFunctions` | on |
| Accept Completions with Commit Characters | `completion.commitCharactersEnabled` | on |
| AI Completions, Provider, Base URL, Model | `aiCompletion.enabled`, `.backend`, `.baseURL`, `.model` | off, Anthropic |
