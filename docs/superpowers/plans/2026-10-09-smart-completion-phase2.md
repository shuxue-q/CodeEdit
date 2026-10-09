# Smart Completion — Phase 2 Implementation Plan (CLion-style semantic ranking)

Spec: `docs/superpowers/specs/2026-10-09-smart-completion-engine-design.md`, section "Phase 2".
Phase 1 landed on `main` in merge commit `7b247964` (see
`docs/superpowers/plans/2026-10-09-smart-completion-phase1.md` for what exists now).
Branch: `feat/smart-completion-phase2` (cut from `main`; never merged or pushed without the
user's instruction).

Language scope stays C and C++ with clangd. Every new signal must respect the phase 1 latency
budget: the popup opens or updates within 500 ms, never later than 1 s. Any LSP request made
for ranking (hover, signature help) is bounded with `awaitValue(of:upTo:)` from
`CodeEdit/Utils/TaskRace.swift`, cached, and skipped without penalty when it times out.

Work through the steps in order. Each step ends with: build passes, the new tests pass,
`swiftlint --strict` is clean for the touched files (pre-existing violations in `FeatureIcon`,
`OpenQuicklyListItemView`, `PDFFileView`, `InspectorTab`, `RainbowBracketTests` are known and
not yours), and one commit on the branch with a `feat(completion): ...` message. Do not start the
next step with a red build.

## Step 0 — Baseline

- Copy this plan into `docs/superpowers/plans/2026-10-09-smart-completion-phase2.md` in the
  worktree, read the spec and the phase 1 plan, read `CLAUDE.md`.
- Build and run the whole `CodeEditTests/Features/Completion` directory's suites plus
  `CodeEditTests/LSPCompletionTests` to confirm the baseline. Commit the plan.

## Step 1 — Expected-type inference (spec phase 2, item 1)

New: `CodeEdit/Features/Completion/Semantics/ExpectedTypeResolver.swift`,
`.../Semantics/TypeText.swift` (normalisation + match), `.../Semantics/CandidateTypeParser.swift`.
Changed: `CompletionContext` (adds `expectedType: TypeText?`), `CompletionAggregator+Context.swift`,
`CompletionRanker.swift`, `RankingWeights.swift` (`expectedType: Double = 1.2`,
`convertibleType: Double = 0.5`).
Tests: `ExpectedTypeResolverTests.swift`, `TypeTextTests.swift`, `CandidateTypeParserTests.swift`,
additions to `CompletionRankerTests.swift` and the golden cases.

Slot detection with tree-sitter nodes at the cursor (reuse `TreeSitterClient.nodesAt` the way
`CompletionIntentRecognizer` does), C-family only:

| Slot | How the expected type is found |
| --- | --- |
| `T x = \|`, `x = \|` (`init_declarator`, `assignment_expression`) | Declared type text from the `declaration` node's type child; for a bare `x = ` ask hover on `x` (bounded 200 ms, cached per (document version, identifier)). |
| `return \|` | Return type text of the enclosing `function_definition` (its type child, minus the declarator's pointer/reference tokens). |
| Call argument (`argument_list`) | Active parameter type from `textDocument/signatureHelp` (the client already exposes `requestSignatureHelp`); parameter index from comma count; parse the type out of the parameter label (`const std::string &name` → `std::string`). |
| `if (\|`, `while (\|`, `!\|`, `&& \|` (`condition_clause`, logical operators) | `bool`. |
| `case \|` | Type of the `switch` condition via hover on its expression (bounded, cached). |
| `T{\|`, `T(\|` for constructors | `T` from the call's function node when it is a `type_identifier`. |

Candidate type: `CandidateTypeParser` extracts the result type from clangd's `detail` /
`labelDetails.description` (functions: return type; variables, fields, enumerators: their type;
types and namespaces: none).

`TypeText.normalize` strips `const`, `volatile`, `&`, `&&`, `*` (keep a pointer-depth count),
leading `::`, `std::` is kept but `std::__1::` is collapsed, template arguments kept verbatim.
Match levels: exact (full bonus), convertible (half bonus: numeric family int/long/size_t/
double/float, enum ↔ its underlying int, pointer ↔ bool, `T*` ↔ `nullptr`), none (no bonus,
never a penalty). Types do not get the bonus when the slot expects a value.

Also make the ranker use clangd's `score` field fully: when `candidate.score` is present it
should be the server signal, not blended half-and-half with the index order. Pin that with a test.

## Step 2 — Postfix completion (spec phase 2, item 2)

New: `CodeEdit/Features/Completion/Providers/PostfixCompletionProvider.swift`,
`.../Providers/PostfixTemplates.swift` (table), `CompletionSource.postfix` (badge "Postfix",
priority between `.snippet` and `.keyword`).
Changed: `CompletionAggregator.swift` (register), `CompletionIntentPolicy.swift` (weight 0.6 in
`.memberAccess`, excluded elsewhere), `CompletionDeduplicator` only if a label collides.
Tests: `PostfixCompletionProviderTests.swift`, `PostfixTemplatesTests.swift`.

Templates for C/C++ (label → expansion, `$0` final caret, `${1:...}` tab stops, `expr` is
the expression text):

| Label | Expansion |
| --- | --- |
| `if` | `if (expr) {\n\t$0\n}` |
| `else` | `if (!(expr)) {\n\t$0\n}` |
| `not` | `!(expr)$0` (no parens when expr is a single identifier or call) |
| `while` | `while (expr) {\n\t$0\n}` |
| `for` | `for (const auto &${1:item} : expr) {\n\t$0\n}` (C++ only) |
| `fori` | `for (${1:size_t} ${2:i} = 0; $2 < expr; ++$2) {\n\t$0\n}` |
| `forr` | `for (${1:size_t} ${2:i} = expr - 1; $2 >= 0; --$2) {\n\t$0\n}` |
| `return` | `return expr;$0` |
| `var` | `auto ${1:name} = expr;$0` (C++); `${1:int} ${2:name} = expr;$0` (C) |
| `new` | `new expr($0)` (C++, only when expr is a type name) |
| `par` | `(expr)$0` |
| `cast` | `static_cast<${1:T}>(expr)$0` (C++); `(${1:T})expr$0` (C) |
| `switch` | `switch (expr) {\n\tcase $1:\n\t\t$0\n}` |
| `nn` | `if (expr != nullptr) {\n\t$0\n}` (C++) / `!= NULL` (C) |

Expression range: from the tree-sitter node that ends right before the `.` (identifier,
call_expression, field_expression, subscript_expression, parenthesized_expression, number
or string literal). When no node ends there, offer nothing. The provider only answers in
`.memberAccess` intent for `.`, never for `->` or `::`. Apply replaces `expr.label` with the
expansion through `textView.insertSnippet`, and the acceptance records into the frequency store
like any other candidate. Templates whose label matches the typed prefix exactly outrank LSP
members; otherwise they sit below the matching members.

## Step 3 — Context-keyed statistics for member access (spec phase 2, item 3)

Changed: `CompletionFrequencyStore.swift` (new key level `receiverType`, file format stays
backward compatible, old entries keep loading), `CompletionContext` (`receiverType: String?`),
`CompletionAggregator+Context.swift` (resolve the receiver type), `CompletionRanker.swift`.
Tests: additions to `CompletionFrequencyStoreTests.swift` and `CompletionRankerTests.swift`.

The receiver type comes from hover on the receiver expression before `.` / `->` (bounded
200 ms, cached per (document version, receiver text)), parsed with `TypeText`. When the hover is
unavailable the ranker falls back to the per-intent statistics from phase 1. A member accepted
on a `std::vector<int>` receiver gets its bonus only on receivers of the same normalized type.

## Step 4 — Chain completion (spec phase 2, item 4) — do this last; defer if blocked

New: `CodeEdit/Features/Completion/Providers/ChainCompletionProvider.swift`, a command and
key binding "Complete Chain" (⌃⇧Space) through `CommandManager` and the keybindings feature,
and a `CodeSuggestionTrigger.chain` case or an explicit flag on `CompletionContext`.
Tests: `ChainCompletionProviderTests.swift` with a fake language client.

Approach without editing the user's buffer: the client's text coordinator sends `didChange`
to clangd; use a scratch copy pattern instead: for each first-level candidate `v` whose type is a
class/struct (from `CandidateTypeParser`), request `textDocument/completion` on a temporary
in-memory document (`didOpen` a `file:///…/chain-scratch.cpp` with the current text plus
`v.` at the cursor, request, `didClose`). Bound the whole thing by 800 ms and the candidates to
the top 8 first-level items. Results are labeled `v.member` and apply as plain text. If clangd
refuses the scratch document or the budget is not achievable, stop, leave the command out,
and report the blocker instead of shipping a slow feature.

## Step 5 — Golden cases and end-to-end checks

Add golden scenarios for: assignment with a declared type, `return` in a function with a known
return type, a call argument whose parameter type is known, `case` labels, and a postfix
template outranking a member on an exact label. Add to
`ClangdCompletionIntegrationTests.swift` (skips when clangd is missing): expected-type
bonus with a real clangd on `std::string s = ` and the postfix `.if` expansion.

## Verification before reporting

- Full build, `swiftlint --strict` at the repo root and inside `CodeEditSourceEditor` if touched.
- All `CodeEditTests/Features/Completion` suites, `LSPCompletionTests`, and the phase 1 latency
  tests must still pass; report the latency numbers if they change.
- Report each phase 2 feature as verified (test or real clangd), not verified, or blocked,
  separately, and list the deviations from the spec.
- Do not merge into `main`, do not push. Report back with the commit list.
