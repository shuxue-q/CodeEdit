# Completion Item Icons and Colors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set appropriate SF Symbols and Xcode-inspired semantic colors for completion items in CodeEdit's completion window (focusing on C/C++ clangd completions), and fix icon rendering and alignment in `CodeEditSourceEditor`.

**Architecture:** Refactor `LSPCompletionEntry` to classify `CompletionItem` based on `CompletionItemKind` and heuristics for C/C++ typedefs/aliases and macros into 14 distinct categories. Update `CodeSuggestionLabelView` in `CodeEditSourceEditor` to remove the multi-color style mask that renders single-layer SF Symbols in white, and add fixed icon frame alignment.

**Tech Stack:** Swift 5, SwiftUI, AppKit, LanguageServerProtocol, XCTest.

## Global Constraints

- Platform: macOS 14.0+.
- Icons: macOS SF Symbols matching the user's specification.
- Colors: Xcode-style semantic palette (`.purple`, `.cyan`, `.orange`, `.indigo`, `.yellow`, `.brown`, `.green`, `.pink`, `.secondary`).
- Indentation: 4 spaces, spaces over tabs.
- Linting: strict adherence to `.swiftlint.yml`.

---

### Task 1: Refactor `LSPCompletionEntry` with Classifier, SF Symbols, and Xcode Colors

**Files:**
- Modify: `CodeEdit/Features/LSP/Features/Completion/LSPCompletionEntry.swift`

**Interfaces:**
- Produces:
  - `LSPCompletionCategory`: enum representing the completion symbol category
  - `LSPCompletionEntry.image`: `Image` with appropriate SF Symbol
  - `LSPCompletionEntry.imageColor`: `SwiftUI.Color` with appropriate Xcode-style color

- [ ] **Step 1: Write failing test in `CodeEditTests/Features/LSP/LSPCompletionTests.swift`**

```swift
    @MainActor
    func testCompletionItemKindIconsAndColors() {
        let functionEntry = LSPCompletionEntry(item: CompletionItem(label: "myFunc", kind: .function))
        XCTAssertEqual(functionEntry.iconName, "function")
        XCTAssertEqual(functionEntry.imageColor, .purple)

        let variableEntry = LSPCompletionEntry(item: CompletionItem(label: "myVar", kind: .variable))
        XCTAssertEqual(variableEntry.iconName, "shippingbox")
        XCTAssertEqual(variableEntry.imageColor, .cyan)

        let classEntry = LSPCompletionEntry(item: CompletionItem(label: "MyClass", kind: .class))
        XCTAssertEqual(classEntry.iconName, "cube.fill")
        XCTAssertEqual(classEntry.imageColor, .orange)

        let structEntry = LSPCompletionEntry(item: CompletionItem(label: "MyStruct", kind: .struct))
        XCTAssertEqual(structEntry.iconName, "square.3.layers.3d.down.right")
        XCTAssertEqual(structEntry.imageColor, .orange)

        let interfaceEntry = LSPCompletionEntry(item: CompletionItem(label: "MyConcept", kind: .interface))
        XCTAssertEqual(interfaceEntry.iconName, "point.3.connected.trianglepath.dot.ted")
        XCTAssertEqual(interfaceEntry.imageColor, .indigo)

        let typedefEntry = LSPCompletionEntry(item: CompletionItem(label: "MyType", kind: .interface, detail: "typedef int MyType"))
        XCTAssertEqual(typedefEntry.iconName, "character.cursor.ibeam")
        XCTAssertEqual(typedefEntry.imageColor, .orange)

        let enumEntry = LSPCompletionEntry(item: CompletionItem(label: "MyEnum", kind: .enum))
        XCTAssertEqual(enumEntry.iconName, "list.bullet.rectangle")
        XCTAssertEqual(enumEntry.imageColor, .orange)

        let enumMemberEntry = LSPCompletionEntry(item: CompletionItem(label: "MY_ENUM_VAL", kind: .enumMember))
        XCTAssertEqual(enumMemberEntry.iconName, "numbersign")
        XCTAssertEqual(enumMemberEntry.imageColor, .yellow)

        let macroEntry = LSPCompletionEntry(item: CompletionItem(label: "MY_MACRO", kind: .constant))
        XCTAssertEqual(macroEntry.iconName, "number")
        XCTAssertEqual(macroEntry.imageColor, .brown)

        let moduleEntry = LSPCompletionEntry(item: CompletionItem(label: "MyNamespace", kind: .module))
        XCTAssertEqual(moduleEntry.iconName, "shippingbox.and.arrow.backward")
        XCTAssertEqual(moduleEntry.imageColor, .green)

        let keywordEntry = LSPCompletionEntry(item: CompletionItem(label: "while", kind: .keyword))
        XCTAssertEqual(keywordEntry.iconName, "key")
        XCTAssertEqual(keywordEntry.imageColor, .pink)

        let snippetEntry = LSPCompletionEntry(item: CompletionItem(label: "for", kind: .snippet))
        XCTAssertEqual(snippetEntry.iconName, "chevron.left.forwardslash.chevron.right")
        XCTAssertEqual(snippetEntry.imageColor, .secondary)

        let fileEntry = LSPCompletionEntry(item: CompletionItem(label: "stdio.h", kind: .file))
        XCTAssertEqual(fileEntry.iconName, "doc.text")
        XCTAssertEqual(fileEntry.imageColor, .secondary)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme CodeEdit -destination "platform=macOS,arch=arm64" -only-testing:CodeEditTests/LSPCompletionTests/testCompletionItemKindIconsAndColors -skipPackagePluginValidation`
Expected: FAIL (compilation error: `iconName` does not exist on `LSPCompletionEntry` or wrong icon returned)

- [ ] **Step 3: Implement `LSPCompletionCategory` and classification in `LSPCompletionEntry.swift`**

Update `LSPCompletionEntry.swift`:
```swift
    enum Category {
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

    var category: Category {
        Self.category(for: item)
    }

    var iconName: String {
        Self.imageName(for: item)
    }

    var image: Image {
        Image(systemName: iconName)
    }

    var imageColor: SwiftUI.Color {
        Self.color(for: item)
    }
```
Implement `category(for item: CompletionItem) -> Category`:
- `.function`, `.method`, `.constructor` -> `.function`
- `.variable`, `.field`, `.property` -> `.variable`
- `.class` -> `.class`
- `.struct` -> `.struct`
- `.interface`: if detail or label contains `typedef`, `using`, `alias`, `type` -> `.typeAlias`, else `.interface`
- `.enum` -> `.enum`
- `.enumMember` -> `.enumMember`
- `.constant`, `.value`, `.unit` -> `.macro`
- `.module` -> `.namespace`
- `.typeParameter` -> `.typeAlias`
- `.keyword`, `.operator` -> `.keyword`
- `.snippet` -> `.snippet`
- `.file`, `.folder` -> `.file`
- Other -> `.other`

Implement `imageName(for item: CompletionItem) -> String` and `color(for item: CompletionItem) -> SwiftUI.Color` based on the category.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme CodeEdit -destination "platform=macOS,arch=arm64" -only-testing:CodeEditTests/LSPCompletionTests/testCompletionItemKindIconsAndColors -skipPackagePluginValidation`
Expected: PASS

---

### Task 2: Fix SF Symbol Rendering and Alignment in `CodeSuggestionLabelView`

**Files:**
- Modify: `CodeEditSourceEditor/Sources/CodeEditSourceEditor/CodeSuggestion/TableView/CodeSuggestionLabelView.swift:18-25`

**Interfaces:**
- Consumes: `CodeSuggestionEntry.image`, `CodeSuggestionEntry.imageColor`, `CodeSuggestionEntry.deprecated`

- [ ] **Step 1: Check existing `CodeSuggestionLabelView.swift` implementation**

Review lines 18-25 in `CodeEditSourceEditor/Sources/CodeEditSourceEditor/CodeSuggestion/TableView/CodeSuggestionLabelView.swift`.

- [ ] **Step 2: Update `CodeSuggestionLabelView.swift`**

Replace:
```swift
            suggestion.image
                .font(.system(size: font.pointSize + 2))
                .foregroundStyle(
                    .white,
                    suggestion.deprecated ? .gray : suggestion.imageColor
                )
```
With:
```swift
            suggestion.image
                .font(.system(size: font.pointSize + 2))
                .foregroundStyle(suggestion.deprecated ? .gray : suggestion.imageColor)
                .frame(width: max(font.pointSize + 4, 18), alignment: .center)
```

- [ ] **Step 3: Run existing test suite to verify no regressions**

Run: `xcodebuild test -scheme CodeEdit -destination "platform=macOS,arch=arm64" -only-testing:CodeEditTests/LSPCompletionTests -skipPackagePluginValidation`
Expected: PASS

---

### Task 3: Comprehensive Unit Tests & Full Suite Verification

**Files:**
- Modify: `CodeEditTests/Features/LSP/LSPCompletionTests.swift`

**Interfaces:**
- Tests all 14 categories, edge cases (no kind, fallback icons, deprecated items), and C/C++ clangd completion integration.

- [ ] **Step 1: Add edge case and fallback tests to `LSPCompletionTests.swift`**

Test:
- `CompletionItem` with `kind: nil` -> icon `"cube"`, color `.secondary`
- `CompletionItem` with `deprecated: true` -> `deprecated == true`
- Typedef with detail `using IntAlias = int;` -> icon `"character.cursor.ibeam"`, color `.orange`
- C++ concept without typedef detail -> icon `"point.3.connected.trianglepath.dot.ted"`, color `.indigo`

- [ ] **Step 2: Run all completion tests**

Run: `xcodebuild test -scheme CodeEdit -destination "platform=macOS,arch=arm64" -only-testing:CodeEditTests/LSPCompletionTests -skipPackagePluginValidation`
Expected: PASS

- [ ] **Step 3: Run SwiftLint**

Run: `swiftlint --strict` (or check modified files)
Expected: 0 violations.
