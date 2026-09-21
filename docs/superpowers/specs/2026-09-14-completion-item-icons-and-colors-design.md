# Completion Item Icons and Colors Design Specification

## Overview

This document specifies the design for completion item icons and colors in CodeEdit's auto-completion popup, tailored for C/C++ (via `clangd`) and other language servers. It maps code completion items to Apple's SF Symbols and an Xcode-inspired semantic color scheme, and resolves icon rendering and column alignment issues in `CodeEditSourceEditor`.

## Requirements & Mapping

### SF Symbol & Color Mapping

| Category | Symbol Name | Color | Clangd / LSP Source |
| :--- | :--- | :--- | :--- |
| **Function / Method** | `function` | `Color.purple` | `CompletionItemKind.function`, `.method`, `.constructor` |
| **Variable / Field** | `shippingbox` | `Color.cyan` | `CompletionItemKind.variable`, `.field`, `.property` |
| **Class** | `cube.fill` | `Color.orange` | `CompletionItemKind.class` |
| **Struct** | `square.3.layers.3d.down.right` | `Color.orange` | `CompletionItemKind.struct` |
| **Interface / Concept** | `point.3.connected.trianglepath.dot.ted` | `Color.indigo` | `CompletionItemKind.interface` (without type alias markers) |
| **Enum** | `list.bullet.rectangle` | `Color.orange` | `CompletionItemKind.enum` |
| **Enum Member** | `numbersign` | `Color.yellow` | `CompletionItemKind.enumMember` |
| **Macro / Preprocessor** | `number` | `Color.brown` | `CompletionItemKind.constant`, `.value`, `.unit` |
| **Namespace / Module** | `shippingbox.and.arrow.backward` | `Color.green` | `CompletionItemKind.module` |
| **Type / Typedef / Alias** | `character.cursor.ibeam` | `Color.orange` | `CompletionItemKind.typeParameter` or `.interface` with `typedef`/`using`/`alias` in detail/label |
| **Keyword** | `key` | `Color.pink` | `CompletionItemKind.keyword`, `.operator` |
| **Snippet / Template** | `chevron.left.forwardslash.chevron.right` | `Color.secondary` | `CompletionItemKind.snippet` |
| **File / Header** | `doc.text` | `Color.secondary` | `CompletionItemKind.file`, `.folder` |
| **Default Fallback** | `cube` | `Color.secondary` | Other or unspecified kinds |

## Architecture & Detailed Design

### 1. `LSPCompletionEntry.swift` (CodeEdit)

`LSPCompletionEntry` conforms to `CodeSuggestionEntry`. We will refactor `image` and `imageColor` properties to use an internal classifier:

- `category(for item: CompletionItem) -> LSPCompletionCategory`:
  1. Inspect `item.kind`.
  2. If `kind == .interface`, check `item.detail` and `item.label` for keywords like `"typedef"`, `"using"`, `"alias"`, or `"type"`. If matched, classify as `.typeAlias`. Otherwise, classify as `.interface`.
  3. If `kind == .constant` or `.value`, check if it's a macro or numerical constant and classify as `.macro`.
  4. Map the category to:
     - `imageName`: SF Symbol name
     - `color`: `SwiftUI.Color`

```swift
enum LSPCompletionCategory {
    case function
    case variable
    case `class`
    case `struct`
    case interface
    case `enum`
    case enumMember
    case macro
    case namespace
    case typeAlias
    case keyword
    case snippet
    case file
    case other
}
```

### 2. `CodeSuggestionLabelView.swift` (CodeEditSourceEditor)

In `CodeSuggestionLabelView.swift`:
```swift
suggestion.image
    .font(.system(size: font.pointSize + 2))
    .foregroundStyle(suggestion.deprecated ? .gray : suggestion.imageColor)
    .frame(width: max(font.pointSize + 4, 18), alignment: .center)
```

- **Fix**: The existing code calls `.foregroundStyle(.white, suggestion.deprecated ? .gray : suggestion.imageColor)`. On single-layer SF Symbols (such as `function`, `shippingbox`, `cube.fill`, etc.), the two-parameter style treats the single layer as the primary layer (`.white`), completely discarding `imageColor` and making items invisible in light themes. Replacing this with a single foregroundStyle fixes icon coloring for both active and deprecated items.
- **Alignment**: Setting `.frame(width: max(font.pointSize + 4, 18), alignment: .center)` ensures symbols with wide glyphs (e.g. `square.3.layers.3d.down.right`) and narrow glyphs (e.g. `number` or `function`) occupy identical horizontal space, preventing ragged text indentation.

## Testing & Verification

1. **Unit Tests in `LSPCompletionTests.swift`**:
   - Verify every kind produces the specified SF Symbol name and `SwiftUI.Color`.
   - Verify clangd typedef/alias heuristic (`.interface` with detail `typedef int MyTypedef` -> `character.cursor.ibeam` and `Color.orange`).
   - Verify deprecated items are correctly handled.
2. **Integration Tests**:
   - Run `xcodebuild test -only-testing:CodeEditTests/LSPCompletionTests` to confirm that all existing C/C++ member completion and cursor tracking tests continue to pass.
3. **Linting**:
   - Run `swiftlint --strict` to ensure no warnings or errors are introduced.
