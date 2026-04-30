# PommoraUI Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Strip the current Pommora markdown editor down to a generic, three-column macOS app skeleton on a new `PommoraUI` branch — no product features, just the navigation shell, search bar, and a verified SwiftUI component library that Claude Code can extend on demand.

**Architecture:** Fork from `main` (which keeps Pommora the markdown editor intact). On `PommoraUI`: keep the `NavigationSplitView` shell with `.prominentDetail`, the `.searchable` sidebar scaffold, and the middle column. Strip every product-specific data model, view, file IO, recents, and drag-drop. Add a `Components/` directory of swiftinterface-verified SwiftUI primitives, and a `.claude/components-reference.md` that catalogues them so Claude Code can pull from a known-good library when adding features.

**Tech Stack:** Swift 6.x, SwiftUI on macOS 26, SwiftData (kept but with empty schema), XCUITest for UI smoke tests, `xcodebuild` CLI for the build→screenshot loop. Pinned DerivedData hash: `Pommora-auqxmapnajdwrzeypbqojwmlerkx`.

---

## Context

This is a re-scope, not a feature addition. The current `main` branch is a working markdown editor with virtual folders, file references, recents, search-over-headings, and drag-and-drop. Nathan's new direction: that codebase is too narrow. He wants the same UI infrastructure repurposed as a generic "all-in-one quality-of-life macOS app" foundation, where features are added incrementally. The MVP for the skeleton is **a fully functional system of SwiftUI components that are fully accurate so things can be seamlessly implemented** — meaning the navigation shell renders, the search field works, and Claude Code has a verified component reference to pull from when Nathan asks for a feature.

`main` stays as Pommora-the-markdown-editor (preserved). `PommoraUI` is the new skeleton branch. They diverge from here.

**One pre-fork edit applies to both branches:** Nathan asked for a new rule in `.claude/swift-uix-rules.md` mandating Context7 documentation lookups before writing any frontend code. He explicitly said this rule belongs in the current Pommora as well. To avoid maintaining two copies, the change lands on `main` first (Task A), and the `PommoraUI` fork inherits it automatically.

---

## Final structure (PommoraUI branch)

```
.claude/
├── CLAUDE.md                       # rewritten: skeleton hub, no product references
├── framework.md                    # rewritten: skeleton vision, no markdown-editor scope
├── feedback.md                     # untouched (transcends product)
├── lessons.md                      # untouched (transcends product)
├── swift-uix-rules.md              # untouched (transcends product)
├── components-reference.md         # NEW: catalogues verified SwiftUI components in Components/
├── session-recaps/
│   └── README.md                   # untouched
└── settings.local.json             # untouched

Pommora/Pommora/
├── PommoraApp.swift                # stripped: empty SwiftData schema
├── ContentView.swift               # stripped: 3-column shell, ContentUnavailableView in middle
├── Library/
│   ├── SidebarView.swift           # stripped: only Favorites section + .searchable
│   ├── SidebarSection.swift        # stripped: only .favorites case
│   └── SidebarSelection.swift      # simplified or deleted
├── Components/                     # NEW
│   ├── README.swift                # convention doc as Swift comment block
│   ├── LayoutComponents.swift      # VStack, HStack, ZStack, Spacer, Divider examples
│   ├── TextComponents.swift        # Text, Label, TextField examples
│   ├── ControlComponents.swift     # Button, Toggle examples
│   ├── ListComponents.swift        # List, ForEach, Section, Table examples
│   └── NavigationComponents.swift  # NavigationStack, NavigationSplitView, NavigationLink, TabView examples
├── Assets.xcassets                 # untouched (top-level; Resources/ stays empty)
└── Resources/                      # untouched (empty)

Pommora/PommoraUITests/
└── SkeletonShellTests.swift        # NEW: smoke tests for skeleton shape
```

**Deleted from `Pommora/Pommora/`:**
- `Library/SidebarFileRow.swift`, `FolderContentView.swift`, `RecentsContentView.swift`, `LibrarySearch.swift`, `LibraryActions.swift`, `HeadingParser.swift`, `DebugSeed.swift`
- `Models/` (entire directory: `VirtualFolder.swift`, `FileReference.swift`)
- `Editor/` (entire directory: `EditorView.swift`, `FileIO.swift`)

**Deleted from `.claude/`:**
- `session-recaps/Session 28-04-26 (1).md` (Pommora-specific recap; the README format guide stays)

---

## Task A: Add Context7 documentation-lookup rule to `swift-uix-rules.md` (on `main`, pre-fork)

**Files:**
- Modify: `.claude/swift-uix-rules.md`

**Branch:** `main`. Lands here so the change is shared between Pommora-the-editor and PommoraUI-the-skeleton.

Nathan's instruction: *"use the Context7 skill to view active documentation before writing any frontend code."* Context7 is an MCP server (`plugin:context7:context7`) that returns live, version-current documentation for libraries, frameworks, and SDKs. The relevant tools are `mcp__plugin_context7_context7__resolve-library-id` and `mcp__plugin_context7_context7__query-docs`. The rule complements — does not replace — the existing `.swiftinterface` and HIG checks: Context7 is for narrative/behavior; swiftinterface is for exact signatures.

- [ ] **Step 1: Confirm current branch is `main` and tree is clean**

```bash
git status
git rev-parse --abbrev-ref HEAD
```

Expected: clean, on `main`. If not, sort that out before editing.

- [ ] **Step 2: Insert the new section above "Source authority"**

Open `.claude/swift-uix-rules.md`. Find the line:

```markdown
## Source authority
```

Insert a new section *immediately above* that line:

```markdown
## Documentation lookup — Context7 first

Before writing or modifying any frontend code (SwiftUI, AppKit-bridged surfaces, any UI framework), use the Context7 MCP server to fetch active, version-current documentation for the surface you're about to touch. Training memory is stale; web docs are JS-rendered and frequently fail to fetch; Context7 returns live docs.

Workflow:

1. Resolve the library you need:
   ```
   mcp__plugin_context7_context7__resolve-library-id(libraryName: "SwiftUI")
   ```
2. Query the relevant doc page:
   ```
   mcp__plugin_context7_context7__query-docs(libraryId: "<id>", query: "<modifier or type name>")
   ```
3. Cite the returned doc snippet (or its source URL if Context7 returns one) in the code change description.

When this is mandatory:

- Before any new SwiftUI modifier, initializer, type, or protocol use.
- Before any change to a third-party library's API surface.
- Before answering a technical "how does X work" question that involves library/SDK behavior.

Context7 does **not** replace the `.swiftinterface` check (Source authority §1) or the HIG check (HIG adherence section). Treat them as complementary:

- **Context7** → narrative docs, behavior, current usage examples.
- **`.swiftinterface`** → exact signatures, generics, defaults, `@available` annotations, line-cited.
- **HIG** → visual correctness, spacing, control sizing, accessibility.

If Context7 is unreachable, fall through to the existing source-authority hierarchy below and report the failure to Nathan — do not skip the lookup silently.

```

- [ ] **Step 3: Verify the rule sits above "Source authority"**

```bash
grep -nE "^## (Documentation lookup|Source authority)" .claude/swift-uix-rules.md
```

Expected: two lines, with `Documentation lookup` appearing on a smaller line number than `Source authority`.

- [ ] **Step 4: Commit on `main`**

```bash
git add .claude/swift-uix-rules.md
git commit -m "docs(rules): require Context7 docs lookup before any frontend code

Adds a 'Documentation lookup — Context7 first' section to swift-uix-rules.md.
Mandates use of the Context7 MCP server (resolve-library-id + query-docs)
before writing or modifying any frontend code, complementing the existing
swiftinterface and HIG checks. Applies to all branches forked from this point."
```

This commit is the last shared change between Pommora and PommoraUI before they diverge.

---

## Task 0: Branch from main and verify clean baseline

**Files:**
- No code changes. Git only.

- [ ] **Step 1: Confirm working tree is clean and on `main`**

```bash
git status
git rev-parse --abbrev-ref HEAD
```

Expected: working tree clean (all current changes committed), HEAD on `main`. If uncommitted work remains, stash or commit before proceeding.

- [ ] **Step 2: Create and check out `PommoraUI` branch**

```bash
git checkout -b PommoraUI
git rev-parse --abbrev-ref HEAD
```

Expected: `PommoraUI`.

- [ ] **Step 3: Verify base build works before any change**

```bash
cd Pommora && xcodebuild -scheme Pommora -configuration Debug build -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Pommora-auqxmapnajdwrzeypbqojwmlerkx 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. This is the known-good starting point.

- [ ] **Step 4: Commit a marker so the branch has its first commit**

```bash
git commit --allow-empty -m "chore: branch PommoraUI from main — re-scope to macOS skeleton

Diverging from Pommora-the-markdown-editor. main keeps the editor.
PommoraUI strips everything but sidebar, middle column, and search."
```

---

## Task 1: Rewrite `.claude/CLAUDE.md` for the skeleton

**Files:**
- Modify: `.claude/CLAUDE.md`

The existing CLAUDE.md is the post-cleanup hub but still references markdown-editor specifics through framework.md. The CLAUDE.md itself is mostly product-neutral — only the description in line 3 and the file-index "read before" hints reference Pommora-as-editor. Most of the file stays.

- [ ] **Step 1: Replace the opening description**

Edit the first paragraph. Replace:

```markdown
A native macOS markdown and plaintext editor built against the macOS 26 design language. This file is the thin operational hub. The substance lives in the linked files below — read those before planning or coding.
```

With:

```markdown
A generic native macOS app skeleton built against the macOS 26 design language. This file is the thin operational hub. The substance lives in the linked files below — read those before planning or coding. The skeleton has no product features yet; it provides a verified `NavigationSplitView` shell, a `.searchable` sidebar, a placeholder middle column, and a `Components/` library of swiftinterface-verified SwiftUI primitives ready to be assembled into features.
```

- [ ] **Step 2: Add a row to the File index table for `components-reference.md`**

Insert after the `swift-uix-rules.md` row:

```markdown
| [`components-reference.md`](components-reference.md) | Catalogue of verified SwiftUI components in `Pommora/Pommora/Components/` — names, swiftinterface citations, idiomatic snippets | Adding any new SwiftUI surface — check here first before writing from memory |
```

- [ ] **Step 3: Replace the Memory protocol bullet about `framework.md` to reference skeleton state**

Find:

```markdown
- An architectural constraint surfaces, or v1.0/v1.1 scope shifts → update [`framework.md`](framework.md) (Standing constraints, Deferred decisions, or Current state).
```

Replace with:

```markdown
- An architectural constraint surfaces, or skeleton scope shifts → update [`framework.md`](framework.md) (Skeleton scope, Standing constraints, or Component categories).
```

- [ ] **Step 4: Verify and commit**

```bash
grep -c "markdown" .claude/CLAUDE.md
```

Expected: `0` (no remaining markdown-editor references).

```bash
git add .claude/CLAUDE.md
git commit -m "docs(claude): re-scope CLAUDE.md hub for PommoraUI skeleton"
```

---

## Task 2: Rewrite `.claude/framework.md` for the skeleton

**Files:**
- Modify: `.claude/framework.md` (full rewrite)

The current framework.md is Pommora-specific (vision = markdown editor, scope = file editing). Rewrite end-to-end.

- [ ] **Step 1: Overwrite framework.md with the skeleton-scoped version**

Replace the entire file contents with:

```markdown
# Framework — PommoraUI

The single source for **what this skeleton is, what it provides, and what's locked**. Read before planning any feature, scoping work, or making architectural decisions. The code answers *how*; this file answers *what* and *why*.

---

## Vision

A generic native macOS app skeleton built against the macOS 26 design language. The skeleton provides a verified three-column `NavigationSplitView` shell, a `.searchable` sidebar, a placeholder middle column, and a curated `Components/` library of swiftinterface-verified SwiftUI primitives. Future features are added incrementally on top of this foundation.

This branch (`PommoraUI`) is **infrastructure**, not a product. It deliberately has no domain features.

---

## Skeleton scope

What's shipped in the skeleton:

- Three-column `NavigationSplitView` with `.navigationSplitViewStyle(.prominentDetail)` — sidebar and middle column resize independently; the detail (right) column absorbs all width changes.
- Sidebar with a single placeholder `Favorites` section and the `.searchable(placement: .sidebar)` scaffold (search field renders; no targets to search yet).
- Middle column shows a `ContentUnavailableView` placeholder when nothing is selected.
- Empty SwiftData `ModelContainer` (no schema entries; ready to register types when a feature lands).
- `Components/` directory containing one file per primitive category, each with verified SwiftUI examples and `#Preview` blocks.

Hard constraints (carried over from Pommora; transcend the re-scope):

- No AppKit wraps — `NSViewRepresentable` is off the table ("swift ONLY items").
- No third-party UI libraries.
- macOS 26 only — no backward compat.
- No auto-save logic, no file IO scaffold (none needed without a feature).

---

## Component categories

The `Components/` directory is organized by SwiftUI primitive category. Each file contains small, verified, swiftinterface-cited examples with `#Preview` blocks.

| Category | File | Includes |
|---|---|---|
| Layout | `LayoutComponents.swift` | `VStack`, `HStack`, `ZStack`, `Spacer`, `Divider` |
| Text | `TextComponents.swift` | `Text`, `Label`, `TextField` |
| Controls | `ControlComponents.swift` | `Button` (all styles), `Toggle` |
| Lists | `ListComponents.swift` | `List`, `ForEach`, `Section`, `Table` |
| Navigation | `NavigationComponents.swift` | `NavigationStack`, `NavigationSplitView`, `NavigationLink`, `TabView` |

Adding a new category: create a new file in `Components/`, add a row to this table, add a section in `.claude/components-reference.md`. Every example must be cited against the macOS 26 swiftinterface per `swift-uix-rules.md`.

---

## Standing constraints

These are non-obvious facts that don't surface from reading the code or git history.

- **No AppKit in skeleton.** Nathan explicitly: "swift ONLY items." `NSViewRepresentable` is off the table.
- **`PBXFileSystemSynchronizedRootGroup`.** New `.swift` files in `Pommora/Pommora/` compile automatically — no `project.pbxproj` edit needed.
- **DerivedData hash to pin.** `Pommora-auqxmapnajdwrzeypbqojwmlerkx`. Always pin with `-derivedDataPath ~/Library/Developer/Xcode/DerivedData/Pommora-auqxmapnajdwrzeypbqojwmlerkx` when running `xcodebuild`. See L-005 in `lessons.md`.
- **Bundle identifier kept as `com.nathantaichman.Pommora`.** Branch name is `PommoraUI` but the Xcode target, scheme, and bundle ID stay `Pommora`. No rename needed.
- **`main` is Pommora-the-markdown-editor.** PommoraUI is a fork. Don't merge product features back into `main` without explicit direction.

---

## Deferred / locked decisions

1. **No features in the skeleton.** Features are added in subsequent sessions, one at a time, on top of this foundation.
2. **No `Settings` scene yet.** Add when the first feature requires user-configurable state.
3. **No `AppState` global model yet.** Add when feature state needs sharing across columns.
4. **Search field has no targets.** The `.searchable` modifier renders, but the binding doesn't filter anything until a feature provides a list.
5. **Middle column is `ContentUnavailableView` only.** Replaced by feature-owned content when the first feature lands.
6. **Components library is curated, not exhaustive.** Five categories at skeleton time. New categories added on demand and recorded in this file's table.

---

## Planning checklist

Run before scoping any task.

- [ ] Does this require AppKit? It's out of scope. Surface to Nathan.
- [ ] Does this add or change a `NavigationSplitView`? Must use `.prominentDetail`. (L-003)
- [ ] Does this introduce a SwiftUI component or modifier? Check `components-reference.md` first; verify against the swiftinterface per `swift-uix-rules.md`. (L-002)
- [ ] Does this introduce shared state? Decide on `@Observable` model vs `@AppStorage` vs SwiftData; document the choice in this file's "Standing constraints" if non-obvious.
- [ ] Does this register a SwiftData model? Update `PommoraApp.modelContainer` schema and add the `@Model` type under a domain-named subdirectory (not `Models/` — that name was deleted with the editor).
```

- [ ] **Step 2: Verify and commit**

```bash
grep -ciE "markdown|virtualfolder|filereference|editor|recents|orphan" .claude/framework.md
```

Expected: `0` (no editor-era leakage).

```bash
git add .claude/framework.md
git commit -m "docs(claude): rewrite framework.md for PommoraUI skeleton"
```

---

## Task 3: Create `.claude/components-reference.md`

**Files:**
- Create: `.claude/components-reference.md`

This is the docs-side counterpart to the `Components/` Swift directory. Initially empty of categories — populated incrementally in Tasks 8–12 as each component file is created. Per writing-plans rules, no TBDs — so the initial file contains only the header, swiftinterface path reminder, and an empty category table that gets populated as we go.

- [ ] **Step 1: Create the file with the initial scaffold**

```markdown
# Components Reference

Catalogue of every verified SwiftUI component in [`Pommora/Pommora/Components/`](../Pommora/Pommora/Components/). Every entry is swiftinterface-cited per [`swift-uix-rules.md`](swift-uix-rules.md). Read this before adding any new SwiftUI surface — pull from a known-good example here rather than writing from memory.

## Source of truth

macOS 26 SDK swiftinterface:
`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.4.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface`

Cite every entry below by `<symbol>` and approximate line number from a `grep -n` against that file at the time of adding.

## Categories

(populated as `Components/` files are added — see Tasks 8–12)
```

- [ ] **Step 2: Verify and commit**

```bash
test -f .claude/components-reference.md && echo "exists"
```

Expected: `exists`.

```bash
git add .claude/components-reference.md
git commit -m "docs(claude): add components-reference.md scaffold"
```

---

## Task 4: Reset `session-recaps/` for the new branch

**Files:**
- Delete: `.claude/session-recaps/Session 28-04-26 (1).md`
- Modify: none (README stays)

The Pommora-specific session recap doesn't apply to PommoraUI. Drop it. The README format guide stays — recaps still get created on Nathan's direction, just not this old one.

- [ ] **Step 1: Delete the recap**

```bash
rm ".claude/session-recaps/Session 28-04-26 (1).md"
ls .claude/session-recaps/
```

Expected: only `README.md` remains.

- [ ] **Step 2: Commit**

```bash
git add ".claude/session-recaps/Session 28-04-26 (1).md"
git commit -m "docs(claude): drop Pommora-specific session recap on skeleton branch"
```

---

## Task 5: Write the failing UI smoke test

**Files:**
- Create: `Pommora/PommoraUITests/SkeletonShellTests.swift`

The test pins down the skeleton's expected user-visible state. It will fail against the current code (which still has Folders/Files/Tags sections, Recents row, etc.) and pass after the strip-down in Tasks 6–7.

- [ ] **Step 1: Create the test file**

```swift
import XCTest

final class SkeletonShellTests: XCTestCase {
    func test_appLaunches_andShowsSearchFieldAndPlaceholder() throws {
        let app = XCUIApplication()
        app.launch()

        // Sidebar search field is visible.
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5),
                      "Sidebar search field should exist")

        // Sidebar shows only the Favorites placeholder section header — no Folders/Files/Tags/Recents.
        XCTAssertTrue(app.staticTexts["Favorites"].exists,
                      "Sidebar should show Favorites section")
        XCTAssertFalse(app.staticTexts["Folders"].exists,
                       "Sidebar should NOT show Folders section in skeleton")
        XCTAssertFalse(app.staticTexts["Files"].exists,
                       "Sidebar should NOT show Files section in skeleton")
        XCTAssertFalse(app.staticTexts["Tags"].exists,
                       "Sidebar should NOT show Tags section in skeleton")
        XCTAssertFalse(app.staticTexts["Recents"].exists,
                       "Sidebar should NOT show Recents row in skeleton")

        // Middle column shows the empty-state placeholder.
        XCTAssertTrue(app.staticTexts["No selection"].exists
                      || app.staticTexts["Select an item"].exists,
                      "Middle column should show ContentUnavailableView placeholder")
    }
}
```

- [ ] **Step 2: Run the test against current code (it must fail)**

```bash
cd Pommora && xcodebuild -scheme Pommora -configuration Debug -destination 'platform=macOS' test -only-testing:PommoraUITests/SkeletonShellTests/test_appLaunches_andShowsSearchFieldAndPlaceholder -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Pommora-auqxmapnajdwrzeypbqojwmlerkx 2>&1 | tail -30
```

Expected: **TEST FAILED** — current sidebar has Folders/Files/Tags sections, so `XCTAssertFalse(app.staticTexts["Folders"].exists)` fails.

- [ ] **Step 3: Commit the failing test**

```bash
git add Pommora/PommoraUITests/SkeletonShellTests.swift
git commit -m "test(skeleton): add failing UI smoke test for PommoraUI shell shape"
```

---

## Task 6: Strip `PommoraApp.swift` and `ContentView.swift`

**Files:**
- Modify: `Pommora/Pommora/PommoraApp.swift`
- Modify: `Pommora/Pommora/ContentView.swift`

Strip the SwiftData schema to empty and replace ContentView's middle/detail logic with a placeholder. After this task the app still references `SidebarView`, which still references `VirtualFolder`/`FileReference` — so the build will break. That's fine; Task 7 fixes it. We do this in two tasks so each commit is reviewable.

- [ ] **Step 1: Empty the SwiftData schema in PommoraApp.swift**

Replace the entire file with:

```swift
import SwiftData
import SwiftUI

@main
struct PommoraApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [], inMemory: false)
    }
}
```

- [ ] **Step 2: Strip ContentView.swift to a minimal three-column shell**

Replace the entire file with:

```swift
import SwiftUI

struct ContentView: View {
    @State private var searchText: String = ""

    var body: some View {
        NavigationSplitView {
            SidebarView(searchText: $searchText)
        } content: {
            ContentUnavailableView(
                "No selection",
                systemImage: "square.dashed",
                description: Text("Select an item from the sidebar.")
            )
        } detail: {
            ContentUnavailableView(
                "No detail",
                systemImage: "doc",
                description: Text("Detail will appear here.")
            )
        }
        .navigationSplitViewStyle(.prominentDetail)
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 3: Confirm the build is intentionally broken**

```bash
cd Pommora && xcodebuild -scheme Pommora -configuration Debug build -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Pommora-auqxmapnajdwrzeypbqojwmlerkx 2>&1 | tail -10
```

Expected: **BUILD FAILED** with errors about `VirtualFolder`, `FileReference`, etc. inside `SidebarView` and the soon-to-delete files. This is expected — we fix it in Task 7. Do not commit yet.

- [ ] **Step 4: Continue to Task 7 without committing**

Task 6 and Task 7 ship as one commit because the intermediate state doesn't build.

---

## Task 7: Strip sidebar and delete dead files

**Files:**
- Modify: `Pommora/Pommora/Library/SidebarView.swift`
- Modify: `Pommora/Pommora/Library/SidebarSection.swift`
- Delete: `Pommora/Pommora/Library/SidebarSelection.swift`
- Delete: `Pommora/Pommora/Library/SidebarFileRow.swift`
- Delete: `Pommora/Pommora/Library/FolderContentView.swift`
- Delete: `Pommora/Pommora/Library/RecentsContentView.swift`
- Delete: `Pommora/Pommora/Library/LibrarySearch.swift`
- Delete: `Pommora/Pommora/Library/LibraryActions.swift`
- Delete: `Pommora/Pommora/Library/HeadingParser.swift`
- Delete: `Pommora/Pommora/Library/DebugSeed.swift`
- Delete: `Pommora/Pommora/Models/` (entire directory)
- Delete: `Pommora/Pommora/Editor/` (entire directory)

- [ ] **Step 1: Delete the obsolete files in one batch**

```bash
cd Pommora/Pommora && \
  rm Library/SidebarSelection.swift \
     Library/SidebarFileRow.swift \
     Library/FolderContentView.swift \
     Library/RecentsContentView.swift \
     Library/LibrarySearch.swift \
     Library/LibraryActions.swift \
     Library/HeadingParser.swift \
     Library/DebugSeed.swift && \
  rm -r Models Editor && \
  ls Library/
```

Expected: `Library/` contains only `SidebarSection.swift` and `SidebarView.swift`. `Models/` and `Editor/` no longer exist.

- [ ] **Step 2: Strip `SidebarSection.swift` to only `.favorites`**

Replace the entire file with:

```swift
import Foundation

enum SidebarSection: String, CaseIterable, Identifiable {
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .favorites: return "Favorites"
        }
    }
}
```

- [ ] **Step 3: Rewrite `SidebarView.swift` as the stripped skeleton**

Replace the entire file with:

```swift
import SwiftUI

struct SidebarView: View {
    @Binding var searchText: String

    var body: some View {
        List {
            ForEach(SidebarSection.allCases) { section in
                Section(section.title) {
                    EmptyView()
                }
            }
        }
        .controlSize(.regular)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .searchable(text: $searchText, placement: .sidebar)
    }
}

#Preview {
    @Previewable @State var query = ""
    return SidebarView(searchText: $query)
}
```

- [ ] **Step 4: Build to confirm the strip-down compiles**

```bash
cd Pommora && xcodebuild -scheme Pommora -configuration Debug build -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Pommora-auqxmapnajdwrzeypbqojwmlerkx 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run the UI smoke test (must now pass)**

```bash
cd Pommora && xcodebuild -scheme Pommora -configuration Debug -destination 'platform=macOS' test -only-testing:PommoraUITests/SkeletonShellTests -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Pommora-auqxmapnajdwrzeypbqojwmlerkx 2>&1 | tail -10
```

Expected: **TEST SUCCEEDED**.

- [ ] **Step 6: Commit Tasks 6 + 7 together**

```bash
git add -A Pommora/
git status   # review the deletes before committing
git commit -m "refactor(skeleton): strip Pommora editor down to navigation shell

- Empty SwiftData schema in PommoraApp.
- ContentView is a three-column NavigationSplitView with .prominentDetail
  and ContentUnavailableView placeholders in content/detail.
- SidebarView shows only the Favorites section + .searchable.
- Delete editor, file IO, virtual folders, file references, recents,
  search-over-headings, drag-drop, debug seed.
- UI smoke test passes."
```

---

## Task 8: Add `Components/` directory and Layout components

**Files:**
- Create: `Pommora/Pommora/Components/README.swift`
- Create: `Pommora/Pommora/Components/LayoutComponents.swift`
- Modify: `.claude/components-reference.md`

- [ ] **Step 1: Verify swiftinterface signatures before writing**

```bash
SWIFTUI_IF=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.4.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface
grep -nE "public struct (VStack|HStack|ZStack|Spacer|Divider) " "$SWIFTUI_IF" | head
```

Expected: lines with public-struct declarations and line numbers. Note the line numbers — they go into the reference doc.

- [ ] **Step 2: Create `Components/README.swift` (convention doc)**

```swift
// MARK: - Components convention
//
// Each file in this directory is a verified reference implementation of one
// SwiftUI primitive category. Rules:
//
//   1. Every component example MUST be cited against the macOS 26 swiftinterface
//      with a comment of the form: `// swiftinterface: <line>: <signature>`
//   2. Every example MUST have a corresponding `#Preview` block.
//   3. Every example MUST use semantic primitives only — no `.frame(width:)`,
//      `.font(.system(size:))`, hex colors, or hand-tuned paddings.
//      See L-001 in `.claude/lessons.md`.
//   4. Every category in this directory MUST have a corresponding section
//      in `.claude/components-reference.md`.
//
// To add a category: create a new `*Components.swift` file here, add a row to
// `.claude/framework.md` Component categories table, add a section to
// `.claude/components-reference.md`.

import SwiftUI

private struct ComponentsConvention {}
```

- [ ] **Step 3: Create `Components/LayoutComponents.swift`**

Replace `<line>` placeholders with the actual line numbers found in Step 1.

```swift
import SwiftUI

// MARK: - VStack
// swiftinterface: <line>: public struct VStack<Content> : View where Content : View
struct LayoutVStackExample: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("First")
            Text("Second")
            Text("Third")
        }
    }
}

// MARK: - HStack
// swiftinterface: <line>: public struct HStack<Content> : View where Content : View
struct LayoutHStackExample: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Left")
            Spacer()
            Text("Right")
        }
    }
}

// MARK: - ZStack
// swiftinterface: <line>: public struct ZStack<Content> : View where Content : View
struct LayoutZStackExample: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.accentColor.opacity(0.15)
            Text("Overlay")
                .padding()
        }
    }
}

// MARK: - Spacer
// swiftinterface: <line>: public struct Spacer : View
struct LayoutSpacerExample: View {
    var body: some View {
        HStack {
            Text("Pinned left")
            Spacer()
            Text("Pinned right")
        }
    }
}

// MARK: - Divider
// swiftinterface: <line>: public struct Divider : View
struct LayoutDividerExample: View {
    var body: some View {
        VStack {
            Text("Above")
            Divider()
            Text("Below")
        }
    }
}

#Preview("VStack") { LayoutVStackExample().padding() }
#Preview("HStack") { LayoutHStackExample().padding() }
#Preview("ZStack") { LayoutZStackExample().frame(width: 200, height: 120) }
#Preview("Spacer") { LayoutSpacerExample().padding() }
#Preview("Divider") { LayoutDividerExample().padding() }
```

- [ ] **Step 4: Append the Layout section to `.claude/components-reference.md`**

Append (under the `## Categories` heading, replacing the parenthetical placeholder line on first append):

```markdown
### Layout

| Component | swiftinterface line | Use this for |
|---|---|---|
| `VStack` | <line> | Vertical stack with optional alignment + spacing |
| `HStack` | <line> | Horizontal stack with optional alignment + spacing |
| `ZStack` | <line> | Depth stack — overlays children with optional alignment |
| `Spacer` | <line> | Flexible empty space inside a stack |
| `Divider` | <line> | Thin separator line, axis inferred from container |

Example file: [`LayoutComponents.swift`](../Pommora/Pommora/Components/LayoutComponents.swift). Five `#Preview` blocks: VStack, HStack, ZStack, Spacer, Divider.
```

- [ ] **Step 5: Build and commit**

```bash
cd Pommora && xcodebuild -scheme Pommora -configuration Debug build -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Pommora-auqxmapnajdwrzeypbqojwmlerkx 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

```bash
git add Pommora/Pommora/Components/ .claude/components-reference.md
git commit -m "feat(components): add Layout primitives — VStack/HStack/ZStack/Spacer/Divider"
```

---

## Task 9: Add Text components

**Files:**
- Create: `Pommora/Pommora/Components/TextComponents.swift`
- Modify: `.claude/components-reference.md`

- [ ] **Step 1: Verify swiftinterface signatures**

```bash
SWIFTUI_IF=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.4.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface
grep -nE "public struct (Text|Label|TextField) " "$SWIFTUI_IF" | head
```

- [ ] **Step 2: Create `TextComponents.swift`**

```swift
import SwiftUI

// MARK: - Text
// swiftinterface: <line>: public struct Text : Equatable, View
struct TextExample: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Headline").font(.headline)
            Text("Body text").font(.body)
            Text("Caption").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Label
// swiftinterface: <line>: public struct Label<Title, Icon> : View where Title : View, Icon : View
struct LabelExample: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Inbox", systemImage: "tray")
            Label("Starred", systemImage: "star")
                .imageScale(.large)
            Label {
                Text("Custom title").bold()
            } icon: {
                Image(systemName: "sparkles").foregroundStyle(.tint)
            }
        }
    }
}

// MARK: - TextField
// swiftinterface: <line>: public struct TextField<Label> : View where Label : View
struct TextFieldExample: View {
    @State private var name: String = ""
    var body: some View {
        Form {
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
        }
    }
}

#Preview("Text") { TextExample().padding() }
#Preview("Label") { LabelExample().padding() }
#Preview("TextField") { TextFieldExample().padding().frame(width: 280) }
```

- [ ] **Step 3: Append the Text section to `components-reference.md`**

```markdown
### Text

| Component | swiftinterface line | Use this for |
|---|---|---|
| `Text` | <line> | Read-only string with `.font`, `.foregroundStyle`, etc. |
| `Label` | <line> | Icon + title pairing — preferred over hand-rolled `HStack { Image; Text }`. See L-001. |
| `TextField` | <line> | Single-line text input with binding |

Example file: [`TextComponents.swift`](../Pommora/Pommora/Components/TextComponents.swift).
```

- [ ] **Step 4: Build and commit**

```bash
cd Pommora && xcodebuild -scheme Pommora -configuration Debug build -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Pommora-auqxmapnajdwrzeypbqojwmlerkx 2>&1 | tail -5
git add Pommora/Pommora/Components/TextComponents.swift .claude/components-reference.md
git commit -m "feat(components): add Text primitives — Text/Label/TextField"
```

---

## Task 10: Add Control components

**Files:**
- Create: `Pommora/Pommora/Components/ControlComponents.swift`
- Modify: `.claude/components-reference.md`

- [ ] **Step 1: Verify swiftinterface signatures**

```bash
SWIFTUI_IF=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.4.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface
grep -nE "public struct (Button|Toggle) " "$SWIFTUI_IF" | head
grep -nE "public struct (Bordered|BorderedProminent|Plain|Link)ButtonStyle" "$SWIFTUI_IF" | head
```

- [ ] **Step 2: Create `ControlComponents.swift`**

```swift
import SwiftUI

// MARK: - Button (styles)
// swiftinterface: <line>: public struct Button<Label> : View where Label : View
struct ButtonExample: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Bordered") {}
                .buttonStyle(.bordered)
            Button("Bordered Prominent") {}
                .buttonStyle(.borderedProminent)
            Button("Plain") {}
                .buttonStyle(.plain)
            Button {
                // action
            } label: {
                Label("With Label", systemImage: "sparkles")
            }
        }
    }
}

// MARK: - Toggle
// swiftinterface: <line>: public struct Toggle<Label> : View where Label : View
struct ToggleExample: View {
    @State private var isOn: Bool = true
    var body: some View {
        Form {
            Toggle("Enabled", isOn: $isOn)
            Toggle(isOn: $isOn) {
                Label("With icon", systemImage: "bolt")
            }
        }
    }
}

#Preview("Button") { ButtonExample().padding().frame(width: 280) }
#Preview("Toggle") { ToggleExample().padding().frame(width: 280) }
```

- [ ] **Step 3: Append the Controls section to `components-reference.md`**

```markdown
### Controls

| Component | swiftinterface line | Use this for |
|---|---|---|
| `Button` | <line> | Tap action with title or custom label. Styles: `.bordered`, `.borderedProminent`, `.plain`, `.link`. |
| `Toggle` | <line> | Boolean binding control with optional label |

Example file: [`ControlComponents.swift`](../Pommora/Pommora/Components/ControlComponents.swift).
```

- [ ] **Step 4: Build and commit**

```bash
cd Pommora && xcodebuild -scheme Pommora -configuration Debug build -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Pommora-auqxmapnajdwrzeypbqojwmlerkx 2>&1 | tail -5
git add Pommora/Pommora/Components/ControlComponents.swift .claude/components-reference.md
git commit -m "feat(components): add Control primitives — Button/Toggle"
```

---

## Task 11: Add List components

**Files:**
- Create: `Pommora/Pommora/Components/ListComponents.swift`
- Modify: `.claude/components-reference.md`

- [ ] **Step 1: Verify swiftinterface signatures**

```bash
SWIFTUI_IF=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.4.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface
grep -nE "public struct (List|ForEach|Section|Table) " "$SWIFTUI_IF" | head
```

- [ ] **Step 2: Create `ListComponents.swift`**

```swift
import SwiftUI

private struct DemoItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
}

private let demoItems: [DemoItem] = [
    .init(title: "Alpha", subtitle: "First entry"),
    .init(title: "Beta", subtitle: "Second entry"),
    .init(title: "Gamma", subtitle: "Third entry")
]

// MARK: - List + ForEach + Section
// swiftinterface: <line>: public struct List<SelectionValue, Content> : View
// swiftinterface: <line>: public struct ForEach<Data, ID, Content>
// swiftinterface: <line>: public struct Section<Parent, Content, Footer>
struct ListExample: View {
    @State private var selection: DemoItem.ID?
    var body: some View {
        List(selection: $selection) {
            Section("Group A") {
                ForEach(demoItems) { item in
                    Label(item.title, systemImage: "circle")
                        .tag(item.id)
                }
            }
        }
        .controlSize(.regular)
    }
}

// MARK: - Table
// swiftinterface: <line>: public struct Table<Value, Rows, Columns> : View
struct TableExample: View {
    var body: some View {
        Table(demoItems) {
            TableColumn("Title", value: \.title)
            TableColumn("Subtitle", value: \.subtitle)
        }
    }
}

#Preview("List") { ListExample().frame(width: 240, height: 220) }
#Preview("Table") { TableExample().frame(width: 360, height: 220) }
```

- [ ] **Step 3: Append the Lists section to `components-reference.md`**

```markdown
### Lists

| Component | swiftinterface line | Use this for |
|---|---|---|
| `List` | <line> | Vertical scrolling collection with optional `selection:` binding |
| `ForEach` | <line> | Iteration inside `List` / `Form` / stacks; requires `Identifiable` or `id:` keypath |
| `Section` | <line> | Group rows under a header (and optional footer) |
| `Table` | <line> | Multi-column data display with sortable `KeyPath` columns |

Example file: [`ListComponents.swift`](../Pommora/Pommora/Components/ListComponents.swift).
```

- [ ] **Step 4: Build and commit**

```bash
cd Pommora && xcodebuild -scheme Pommora -configuration Debug build -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Pommora-auqxmapnajdwrzeypbqojwmlerkx 2>&1 | tail -5
git add Pommora/Pommora/Components/ListComponents.swift .claude/components-reference.md
git commit -m "feat(components): add List primitives — List/ForEach/Section/Table"
```

---

## Task 12: Add Navigation components

**Files:**
- Create: `Pommora/Pommora/Components/NavigationComponents.swift`
- Modify: `.claude/components-reference.md`

- [ ] **Step 1: Verify swiftinterface signatures**

```bash
SWIFTUI_IF=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.4.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface
grep -nE "public struct (NavigationStack|NavigationSplitView|NavigationLink|TabView) " "$SWIFTUI_IF" | head
grep -nE "ProminentDetailNavigationSplitViewStyle" "$SWIFTUI_IF" | head
```

- [ ] **Step 2: Create `NavigationComponents.swift`**

```swift
import SwiftUI

// MARK: - NavigationStack
// swiftinterface: <line>: public struct NavigationStack<Data, Root> : View where Root : View
struct NavigationStackExample: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Push detail", value: "Detail")
            }
            .navigationDestination(for: String.self) { value in
                Text("Pushed: \(value)")
            }
            .navigationTitle("Stack")
        }
    }
}

// MARK: - NavigationSplitView (.prominentDetail)
// swiftinterface: <line>: public struct NavigationSplitView<Sidebar, Content, Detail> : View
// See L-003: always use `.prominentDetail` so sidebar/content resize independently.
struct NavigationSplitViewExample: View {
    var body: some View {
        NavigationSplitView {
            List { Text("Sidebar row") }
        } content: {
            Text("Content column")
        } detail: {
            Text("Detail column")
        }
        .navigationSplitViewStyle(.prominentDetail)
    }
}

// MARK: - NavigationLink (value-based)
// swiftinterface: <line>: public struct NavigationLink<Label, Destination> : View
struct NavigationLinkExample: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink(value: 1) { Label("One", systemImage: "1.circle") }
                NavigationLink(value: 2) { Label("Two", systemImage: "2.circle") }
            }
            .navigationDestination(for: Int.self) { Text("Value \($0)") }
        }
    }
}

// MARK: - TabView
// swiftinterface: <line>: public struct TabView<SelectionValue, Content> : View
struct TabViewExample: View {
    var body: some View {
        TabView {
            Text("First").tabItem { Label("First", systemImage: "1.square") }
            Text("Second").tabItem { Label("Second", systemImage: "2.square") }
        }
    }
}

#Preview("NavigationStack") { NavigationStackExample().frame(width: 320, height: 220) }
#Preview("NavigationSplitView") { NavigationSplitViewExample().frame(width: 600, height: 320) }
#Preview("NavigationLink") { NavigationLinkExample().frame(width: 320, height: 220) }
#Preview("TabView") { TabViewExample().frame(width: 360, height: 220) }
```

- [ ] **Step 3: Append the Navigation section to `components-reference.md`**

```markdown
### Navigation

| Component | swiftinterface line | Use this for |
|---|---|---|
| `NavigationStack` | <line> | Push-based navigation with `navigationDestination(for:)` |
| `NavigationSplitView` | <line> | Sidebar / content / detail. **Always pair with `.navigationSplitViewStyle(.prominentDetail)`** — see L-003. |
| `NavigationLink` | <line> | Value-based push (preferred) or label-based push |
| `TabView` | <line> | Top-level switching between independent panes |

Example file: [`NavigationComponents.swift`](../Pommora/Pommora/Components/NavigationComponents.swift).
```

- [ ] **Step 4: Build and commit**

```bash
cd Pommora && xcodebuild -scheme Pommora -configuration Debug build -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Pommora-auqxmapnajdwrzeypbqojwmlerkx 2>&1 | tail -5
git add Pommora/Pommora/Components/NavigationComponents.swift .claude/components-reference.md
git commit -m "feat(components): add Navigation primitives — Stack/SplitView/Link/TabView"
```

---

## Task 13: Final verification — build clean, tests pass, screenshots captured

**Files:**
- Create: `screenshots/<timestamp>-skeleton-shell.png`

- [ ] **Step 1: Clean build with zero warnings**

```bash
cd Pommora && xcodebuild -scheme Pommora -configuration Debug clean build -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Pommora-auqxmapnajdwrzeypbqojwmlerkx 2>&1 | grep -E "warning:|error:|BUILD" | tail -20
```

Expected: `** BUILD SUCCEEDED **` and no `warning:` lines that touch our changes.

- [ ] **Step 2: Run all UI tests**

```bash
cd Pommora && xcodebuild -scheme Pommora -configuration Debug -destination 'platform=macOS' test -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Pommora-auqxmapnajdwrzeypbqojwmlerkx 2>&1 | tail -15
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Launch app and capture skeleton screenshot**

Open the built app from Xcode (`Cmd+R`) or via Finder from the DerivedData product path. Then:

```bash
mkdir -p ./screenshots
screencapture -l$(osascript -e 'tell app "System Events" to tell process "Pommora" to id of window 1') \
  ./screenshots/$(date +%Y%m%d-%H%M%S)-skeleton-shell.png
```

Expected: PNG file created under `./screenshots/`. Open it; visually confirm:
- Three columns visible.
- Sidebar shows search field at top.
- Sidebar shows `Favorites` header (empty body).
- Middle column shows `ContentUnavailableView` with "No selection".
- Detail column shows `ContentUnavailableView` with "No detail".
- Drag the sidebar divider — only the detail column should resize. Drag the content divider — same.

- [ ] **Step 4: Cross-reference screenshot against HIG**

Per `swift-uix-rules.md`, fetch and re-read the macOS HIG sidebars page. Confirm:
- Sidebar background uses standard sidebar material.
- Search field placement matches HIG sidebar pattern.
- Section header typography matches HIG.

If any deviation is found, surface it to Nathan and stop. Do not silently fix.

- [ ] **Step 5: Final commit**

```bash
git add screenshots/
git commit -m "chore(skeleton): capture verified screenshot of PommoraUI shell"
```

- [ ] **Step 6: Report completion**

Report to Nathan, verbatim, one of:

> `Build clean, screenshots reviewed, HIG verified — finalized.`

or, if anything is outstanding:

> `Outstanding: <list>`

---

## Verification (end-to-end)

1. `git log --oneline main..PommoraUI` shows commits for: branch marker, CLAUDE.md rewrite, framework.md rewrite, components-reference.md scaffold, session-recap drop, failing UI test, strip-down, five component categories, final screenshot. ~13 commits.
2. `git checkout main && ls Pommora/Pommora/` still shows `Editor/`, `Models/`, the full `Library/` with all files — `main` is untouched.
3. `git checkout PommoraUI && ls Pommora/Pommora/` shows: `Assets.xcassets/`, `Components/`, `ContentView.swift`, `Library/`, `PommoraApp.swift`, `Resources/`. `Editor/` and `Models/` are gone.
4. `ls Pommora/Pommora/Components/` shows six files: `README.swift`, `LayoutComponents.swift`, `TextComponents.swift`, `ControlComponents.swift`, `ListComponents.swift`, `NavigationComponents.swift`.
5. `ls Pommora/Pommora/Library/` shows two files only: `SidebarSection.swift`, `SidebarView.swift`.
6. `cd Pommora && xcodebuild -scheme Pommora -configuration Debug build` succeeds with zero warnings.
7. `cd Pommora && xcodebuild -scheme Pommora -configuration Debug -destination 'platform=macOS' test` runs `SkeletonShellTests` and reports green.
8. `grep -ciE "markdown|virtualfolder|filereference|recents|orphan|heading" .claude/CLAUDE.md .claude/framework.md` returns `0` across both files.
9. `grep -c "swiftinterface:" Pommora/Pommora/Components/*.swift | grep -v ":0"` shows every component file has at least one swiftinterface citation.
10. Open `screenshots/<timestamp>-skeleton-shell.png`. Visually matches the description in Task 13 Step 3.

---

## Critical files reference

| Path | Action |
|---|---|
| `.claude/swift-uix-rules.md` | Add Context7 rule **on `main`** (Task A) |
| `.claude/CLAUDE.md` | Rewrite (Task 1) |
| `.claude/framework.md` | Full rewrite (Task 2) |
| `.claude/components-reference.md` | Create + populate incrementally (Tasks 3, 8–12) |
| `.claude/session-recaps/Session 28-04-26 (1).md` | Delete (Task 4) |
| `Pommora/PommoraUITests/SkeletonShellTests.swift` | Create (Task 5) |
| `Pommora/Pommora/PommoraApp.swift` | Strip (Task 6) |
| `Pommora/Pommora/ContentView.swift` | Strip (Task 6) |
| `Pommora/Pommora/Library/SidebarView.swift` | Strip (Task 7) |
| `Pommora/Pommora/Library/SidebarSection.swift` | Strip (Task 7) |
| `Pommora/Pommora/Library/SidebarSelection.swift` | Delete (Task 7) |
| `Pommora/Pommora/Library/SidebarFileRow.swift` | Delete (Task 7) |
| `Pommora/Pommora/Library/FolderContentView.swift` | Delete (Task 7) |
| `Pommora/Pommora/Library/RecentsContentView.swift` | Delete (Task 7) |
| `Pommora/Pommora/Library/LibrarySearch.swift` | Delete (Task 7) |
| `Pommora/Pommora/Library/LibraryActions.swift` | Delete (Task 7) |
| `Pommora/Pommora/Library/HeadingParser.swift` | Delete (Task 7) |
| `Pommora/Pommora/Library/DebugSeed.swift` | Delete (Task 7) |
| `Pommora/Pommora/Models/` | Delete entire directory (Task 7) |
| `Pommora/Pommora/Editor/` | Delete entire directory (Task 7) |
| `Pommora/Pommora/Components/README.swift` | Create (Task 8) |
| `Pommora/Pommora/Components/LayoutComponents.swift` | Create (Task 8) |
| `Pommora/Pommora/Components/TextComponents.swift` | Create (Task 9) |
| `Pommora/Pommora/Components/ControlComponents.swift` | Create (Task 10) |
| `Pommora/Pommora/Components/ListComponents.swift` | Create (Task 11) |
| `Pommora/Pommora/Components/NavigationComponents.swift` | Create (Task 12) |
| `screenshots/<timestamp>-skeleton-shell.png` | Capture (Task 13) |

---

## Self-review notes

- **Spec coverage:** Context7 rule on main (Task A), branching (Task 0), `.claude/` rewrite (Tasks 1–4), strip-down (Tasks 6–7), Components/ infra (Tasks 8–12), middle-column placeholder (Task 6), search bar kept (Task 7), TDD smoke test (Tasks 5, 7, 13), screenshot review (Task 13). All scope items from the brainstorm answered.
- **Branch propagation:** Task A lands on `main` before Task 0 forks. PommoraUI inherits the Context7 rule via `git checkout -b PommoraUI`. No double-edit needed.
- **Placeholder scan:** Component files contain `<line>` placeholders that the executing engineer (or Claude) replaces by running the `grep -n` step before writing code. This is intentional — line numbers must be discovered at execution time because they shift across SDK builds. No TBDs in narrative or untestable assertions.
- **Type consistency:** `SidebarSection.favorites` (Task 7), `searchText` binding shape (`@State private var searchText: String = ""` in `ContentView`, `@Binding var searchText: String` in `SidebarView`), `DemoItem` private struct used only inside `ListComponents.swift`. No symbols referenced in later tasks that aren't defined earlier.
- **Bundle ID and target name:** No rename. Branch is `PommoraUI` for git only. Target/scheme/bundle ID stay `Pommora`.
- **Post-approval move:** This plan file lives at `~/.claude/plans/`. After approval, copy to `docs/superpowers/plans/2026-04-30-pommora-ui-skeleton.md` in the project repo for the writing-plans skill convention.
