# CMake Completion — Design

Date: 2026-10-09
Status: implemented on `feat/completion-cmake`
Builds on `2026-09-28-completion-aggregator-design.md` and
`2026-10-09-smart-completion-engine-design.md`, which describe the pipeline and the intent
recognizer this document extends.

## Problem

Intent recognition and the keyword and snippet tables only understood the C family. In a
`CMakeLists.txt` the recognizer returned `.unknown` almost everywhere (the generic scope lookup does
not know CMake's node names, and the C scanner reads `//` as a comment and `#` as nothing), the
snippet provider had nothing for `cmake`, and every `neocmakelsp` item was weighted with the flat 0.5
of `.unknown`. The popup also stayed closed or stayed open in the wrong places: `src/main.cpp` read as
member access, `3.20` as a number literal, and `# note` was only a comment when a syntax tree happened
to be there.

## What `neocmakelsp` sends

Checked against `neocmakelsp 0.11.2` over stdio: its only completion trigger character is `/`, and it
returns the same list at every position, whatever the cursor is in: about 260 items of kind
`Function` (every command, once in lower case and once in upper case) and about 860 of kind
`Variable` (the built-in variables). It does not know whether the cursor is at a command name, in an
argument or inside `${`, so the client-side intent is what turns that list into a sensible one:
commands first at command position, variables first inside `${`. Since `{` is not a trigger character,
`${` alone does not open the popup; the first letter typed after it does.

## Constraints

- C and C++ behavior does not change. Their recognizer, scanner, token rules, weights and tests stay as
  they are, except one assertion: `testCFamilyScopesDoNotApplyToOtherGrammars` expected `.unknown` for
  `set(CMAKE_` in `cmake`, and now expects the new intent.
- Completion stays independent of CMake workspace discovery (`CMakeProject`, `CMakeWorkspace`). Only the
  document's language id (`cmake`) and its syntax tree are used.
- No new dependency; the vendored `tree-sitter-cmake` grammar is used as it is.

## Intents

CMake has three completion sites, which map onto the shared `CompletionIntent` like this. Two cases
are new; the smallest set that makes the sites distinguishable.

| Site | Example | Intent |
| --- | --- | --- |
| Command name in a function, macro, block, `if`, `foreach` or `while` body | `  add_|` | `.statement` |
| Command name at file scope | `add_|` | `.topLevel` |
| Command argument, after `(` or a space | `target_link_libraries(app PU|` | **`.argument`** (new) |
| Name inside `${`, `$ENV{`, `$CACHE{`, also within quotes | `"${CMAKE_|` | **`.variableReference`** (new) |
| `#` and `#[[ … ]]` comments | `# note|` | `.comment` |
| Quoted and bracket arguments | `message("hel|` | `.string` |

Why only two new cases:

- A command name needs no case of its own. `.statement` and `.topLevel` already mean "something that
  starts a statement or declaration goes here", and they already open the popup. For CMake the two only
  record the scope; they rank alike.
- `.argument` is a genuinely new site: CMake has no expressions, only whitespace-separated arguments
  that are keywords, targets, paths and bare variable names at once. `.expression` would weight
  commands (functions) first, which is wrong there.
- `.variableReference` cannot be `.string` (which suppresses typing) even though it often sits inside
  quotes, and cannot be `.argument` (which allows keywords and weights targets and modules, none of which a variable name is).
- `.memberAccess`, `.scopeAccess`, `.numberLiteral` and `.unknown` are never produced for CMake.
  `src/main.cpp`, `../lib/libfoo.a`, `a->b` and `3.20` are plain arguments, so the window is not
  suppressed.

Both new cases have a `promptDescription` for the AI prompt, and they are handled in the exhaustive
`CompletionIntentPolicy.weight` switch. `CompletionIntent` stays `CaseIterable`; the frequency store keys
intents by `String(describing:)`, so existing data is unaffected.

## Recognition

`CompletionIntentRecognizer.recognize` hands `cmake` documents to `CMakeTokenRules.intent` before any
C-family logic runs. The rules combine the line before the typed prefix (`CMakeLineScanner`) with the
syntax tree's node types (`CMakeKeywords.treeScope`).

### The line scanner

`CMakeLineScanner` lexes one line. It models what the C scanner cannot:

- `#` starts a line comment, `#[=*[` a bracket comment (closed on the line or open). `//` is ordinary.
- Only `"` quotes, and `\` escapes (`\"`, `\${`, `\(`) in quoted and unquoted arguments.
- `[=*[ … ]=*]` bracket arguments. A lone `[` is an ordinary character.
- `${`, `$ENV{` and `$CACHE{` open references, which nest and which also open inside quotes. An unquoted
  reference is cancelled by whitespace, because an unquoted argument ends there.
- Parenthesis depth outside quotes, the last non-blank code character, whether a quote closed exactly at
  the end of the text, and whether the text is blank.

### The decision

In order, the first match wins:

1. **Comment**: the scanner is in a comment, or the innermost known node is `line_comment` or
   `bracket_comment`. This covers multi-line bracket comments, which a single line cannot show.
2. **Variable reference**: the scanner has an open reference (inside quotes too), or the innermost
   known node is a variable node and a prefix has been typed.
3. **String**: the scanner is inside an open quote or bracket argument, or the innermost known node is a
   quoted or bracket argument and the cursor is not right after a quote that closed on this line.
4. **Comment**, for a typed `#` (the aggregator treats `#` as part of the prefix word).
5. **Argument**: a `(` is open on the line.
6. **Command name**: nothing but whitespace or a finished comment precedes the prefix, unless the tree
   says an earlier line's argument list is still open (a continuation line, which is an argument). Also
   after a finished command on the same line (`endif() add_`).
7. **Argument**, for anything else that precedes the prefix without a `(` (`    main.cpp util`, the
   continuation of an argument list).

The scope of a command name comes from the tree: the nearest body node (`body`, `if_condition`,
`function_def`, `macro_def`, `block_def`, `foreach_loop`, `while_loop`) means `.statement`, `source_file`
means `.topLevel`. Without any tree, indentation decides: an indented line is `.statement`.

### What the tree is trusted for

Incomplete code parses as `ERROR`. Typing `add_` in a function body gives `[identifier, ERROR,
source_file]`: the enclosing `function_def` is not an ancestor, so the scope comes out `.topLevel`.
That is harmless, since CMake's two command-position intents rank identically, and it is why
`treeScope` skips `ERROR` and anonymous nodes (`(`, `}`, `ENV`) and looks for the first known ancestor.
The tree is never trusted for the cursor's exact node. The grammar's external scanner also emits a
zero-width `bracket_argument_content` at the end of an unfinished command, so that node type is
deliberately not mapped to `.string`. A command-name node (`identifier`, `endif`, …) before a header node
means the cursor is on the name, not in the parentheses.

## Tables

`Providers/CMakeCompletionTables.swift`, wired into `TreeSitterSnippetProvider` under `"cmake"`:

| Table | Entries | Intents | Kind offered as |
| --- | --- | --- | --- |
| Flow-control and definition commands | `if`, `elseif`, `else`, `endif`, `foreach`, …, `return`, `break`, `continue` | `.statement`, `.topLevel`, `.unknown` | `.function` |
| Common commands | `cmake_minimum_required`, `project`, `add_executable`, …, `FetchContent_MakeAvailable` | same | `.function` |
| Keyword arguments | `PUBLIC`, `PRIVATE`, `REQUIRED`, `VERSION`, `STATUS`, `ON`, `AND`, `IN_LIST`, … | `.argument` | `.keyword` |
| Variables | `CMAKE_SOURCE_DIR`, `CMAKE_CXX_STANDARD`, `PROJECT_NAME`, `APPLE`, … | `.argument`, `.variableReference` | `.variable` |
| Snippets | `cmake_minimum_required`, `project`, `add_executable`, `add_library`, `target_link_libraries`, `if`, `if else`, `foreach`, `while`, `function`, `macro`, `option`, `find_package`, `install(TARGETS …)`, `add_custom_command` | command intents | `.snippet` |

Commands are offered as `.function` and variables as `.variable`, the kinds `neocmakelsp` uses, so
`CompletionDeduplicator` merges a name both sources offer into one row (the server's item wins). `Keyword` table entries gained a `kind` for this (default `.keyword`, so C and C++ are unchanged). A snippet
and a server command with the same label stay separate rows, because they differ in kind: that is how
`add_executable` shows both the server item and the placeholder template. The deduplicator drops a
plain keyword when a snippet has the same label, as it does for C. Variables are listed for arguments
too, since `set(CMAKE_CXX_STANDARD 17)` and `if(APPLE)` name them without braces.

Snippet bodies use the LSP syntax with two-space indentation (CMake's convention). Single-line
commands end at their `)`, with the cursor on the last placeholder's tab stop; block commands put `$0`
on the indented body line.

## Ranking

`CompletionIntentPolicy.weight` gained a defaulted `languageId` parameter (threaded through
`CompletionRanker.rank`), because `.statement` and `.topLevel` mean something else in CMake. For `cmake`:

| Intent | Weights (kind) |
| --- | --- |
| `.statement`, `.topLevel` | function 1.0, snippet 0.95, keyword 0.9, everything else 0.2 |
| `.variableReference` | variable 1.0, macro and enum member 0.9, module and path 0.3, other 0.2; snippets and keywords excluded |
| `.argument` | variable 0.9, module and file 0.8, keyword 0.8, constant 0.8, folder 0.7, function 0.5, other 0.3; snippets excluded |

`prefixShapeBonus` takes an optional intent: for `.argument` an `ALL_CAPS` prefix gives keywords the
same +0.3 that macros and enumerators already get, so `PU` ranks `PUBLIC` above a variable that happens
to match. Without an intent, the function is unchanged. The server's own items keep their `sortText`
and score signals as usual.

Typing opens the window for all four of command position, argument position and `${`
(`allowsAutomaticCompletion` is true for them) and stays closed in comments and plain quoted text.
Document words (weight 0.25) are also offered in `.argument` and `.variableReference`: target and
variable names from the file that the server may not know.

## Out of scope

- `$<…>` generator expressions get no intent of their own; they are arguments.
- Command-specific argument grammars (which keyword follows `install(`) are not modeled.
- Completion keeps no knowledge of CMake workspace state (presets, targets from the build tree).
- Multi-line context for quotes and bracket arguments comes from the syntax tree only; without a tree
  a line inside a multi-line string is read as code.

## Tests

`CMakeIntentRecognizerTests`, `CMakeLineScannerTests`, `CMakeCompletionPolicyTests` (weights, typing
gate, end-to-end ranking through the deduplicator and ranker) and `CMakeCompletionTablesTests`, all in
`CodeEditTests/Features/Completion/`, plus `CMakeCompletionIntegrationTests`, which drives the aggregator on
a `CMakeLists.txt` with a real `neocmakelsp`, syntax tree and editor controller (skipped when the server is not
installed; headless, so no popup drawing or key handling). `neocmakelsp`'s 2 MB answer can miss the 800 ms
server deadline in a debug build; it is then merged in on the next cursor move, which the tests reproduce.
Recognizer cases run with node types where the tree is the deciding signal (continuation lines,
multi-line comments and quotes, command names) and without where the line is. The existing C-family tests pass unchanged.
