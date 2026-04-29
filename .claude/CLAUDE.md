# Pommora — Project Context

A native macOS markdown and plaintext editor built against the macOS 26 design language. Folder-based (virtual folders containing references to files anywhere on disk), aesthetically aligned with current Apple Design Resources, fully native SwiftUI.

The full product spec lives in [`PRD`](../PRD) at the repo root. This file is the **operational** context for working in the codebase.

## Stack

- **Swift 6.x**, **SwiftUI** shell
- **SwiftData** for persistence (local only — no cloud, no accounts)
- **AppKit** (`NSViewRepresentable`-wrapped `NSTextView`) for the editor pane in v1.1; v1.0 MVP uses plain `TextEditor`
- **Minimum macOS**: 26 only. No fallback support for earlier versions.
- **Xcode project**: at `Pommora/Pommora.xcodeproj`. Uses **`PBXFileSystemSynchronizedRootGroup`** — any file added to `Pommora/Pommora/`, `Pommora/PommoraTests/`, or `Pommora/PommoraUITests/` is auto-compiled. No need to register files in `project.pbxproj`.

## Repository layout

```
.                                       # repo root (Project Pommora/)
├── PRD                                 # source-of-truth product spec
├── README.md
├── .claude/
│   ├── CLAUDE.md                       # this file
│   ├── feedback.md                     # Nathan's direct behavior corrections
│   ├── memory.md                       # non-obvious project state + decisions
│   └── lessons/                        # one file per failure pattern
├── docs/
│   └── design/                         # Figma file, screenshots — reference only
└── Pommora/                            # Xcode project root
    ├── Pommora.xcodeproj/
    └── Pommora/                        # all Swift source (synchronized group)
        ├── PommoraApp.swift
        ├── ContentView.swift
        ├── Library/                    # Sidebar, FolderContent, Recents, search, actions
        ├── Editor/                     # EditorView, FileIO
        ├── Models/                     # VirtualFolder, FileReference
        └── Resources/                  # Assets.xcassets only
```

## Workflow rules

**Edit Swift in VS Code, run in Xcode.** Nathan strongly prefers to avoid Xcode for editing.

| Task | Where |
|---|---|
| Edit `.swift` files | VS Code (Swift extension by swiftlang) |
| Build (CLI) | `cd Pommora && xcodebuild -scheme Pommora -configuration Debug build` |
| Run / debug | Xcode `Cmd+R` |
| SwiftUI Previews | Xcode only |
| Edit `Info.plist`, `*.entitlements`, `*.xcassets/Contents.json` | VS Code (text formats) |
| Add a new `.swift` file | Create it in `Pommora/Pommora/<subdir>/` — synchronized groups pick it up automatically |
| Adjust target settings, schemes, capabilities | Xcode (rare) |

## Memory protocol

**Memory is mandatory, not optional.** Every session that surfaces a non-obvious correction, a new constraint, or a mistake should update at least one memory location before closing. Skipping this is how the same mistakes happen twice.

Three-tier rule from `~/.claude/CLAUDE.md`:

1. **Global preferences** → `~/.claude/CLAUDE.md`
2. **Project context** (code facts, behavior contracts, deferred decisions) → this file
3. **Project memory** (non-obvious corrections, session state, feedback rules) → `~/.claude/projects/<proj>/memory/*.md`

This project also keeps two supplementary files **in the repo** (checked in, readable in VS Code):

- [`.claude/feedback.md`](feedback.md) — Nathan's direct behavior corrections, expanded narratively
- [`.claude/memory.md`](memory.md) — non-obvious project state and decisions not derivable from the code

**When to write:**

- Nathan corrects your behavior → write a feedback entry immediately, before moving on
- A bug or mistake is discovered and fixed → append a dated incident to the relevant lessons file
- An architectural constraint surfaces (something that blocked or re-scoped work) → add it to `.claude/memory.md`
- A session ends with significant changes → update `.claude/memory.md` with what changed and what was deferred

**What to write:** the non-obvious part. If it's in the code or git history, don't duplicate it. Write the *why*, the *constraint*, the *decision that surprised you*, or the *mistake pattern* — so future sessions don't have to rediscover it.

Write to both `~/.claude/projects/<proj>/memory/` (for auto-memory recall) **and** update the repo files (for in-context reference) when a session surfaces something worth keeping.

## Lessons (required reading — never repeat the same mistake twice)

Mistakes already made on Pommora live in [`.claude/lessons/`](lessons/). **Read the relevant file before doing the matching kind of work.**

| Before you do this | Read this |
|---|---|
| Any UI change (sizing, fonts, icon scale, padding, row heights, color, materials, drag/drop, animations) | [`lessons/ui-dimensions-and-semantic-primitives.md`](lessons/ui-dimensions-and-semantic-primitives.md) |
| Introducing or modifying any SwiftUI modifier, initializer, or protocol use | [`lessons/swiftui-api-verification.md`](lessons/swiftui-api-verification.md) |
| Any `NavigationSplitView` layout or column-width change | [`lessons/navigation-split-view-columns.md`](lessons/navigation-split-view-columns.md) |

When Nathan flags a new mistake, **append a dated incident** to the matching lesson file, or create a new file and link it from [`lessons/README.md`](lessons/README.md) and the table above.

## Deferred / locked product decisions

Decisions that constrain future work. Behavior already in code is **not** documented here — read the code.

1. **MVP cut = walking skeleton.** v1.0 ships without rendering toggle, file watching, or security-scoped bookmarks. Those are v1.1 fixup iterations.
2. **Rendering toggle is deferred.** When it returns: binary only — Raw (mono, plain) / Styled (SF + formatted markdown). The 3-mode design from 2026-04-26 is dropped.
3. **Theme setting** — Settings scene exposes Light / Dark / Device picker (default = Device). App-only override via `.preferredColorScheme(...)`. Stored on `AppState.themePreference`.
4. **Missing files (MVP)** — auto-removed silently on launch. v1.1 (with bookmarks) shifts to inline "Locate…" UX.
5. **Outline panel** — not in MVP. v1.1 Iteration D.
6. **Future view modes** (icon, list, gallery) — deferred. Column view only for now.
7. **`bookmarkData: Data` on `FileReference`** — additive in v1.1 Iteration A. No destructive migration.
8. **No AppKit wraps in v1.0.** `NSViewRepresentable` is off the table until v1.1. Nathan's explicit instruction: "swift ONLY items."

## Behavior contracts

What the app does; the *how* is in the source files.

- **Sidebar** — four top-level sections (`Favorites`, `Folders`, `Files`, `Tags`) plus a `Recents` row at the top. `Favorites` and `Tags` are header-only placeholders. `Folders` lists `VirtualFolder`s as flat rows (no inline file children). `Files` lists orphan `FileReference`s (`folder == nil`) directly in the sidebar `List` — no inner scroll cap, `List` itself scrolls. Section order is user-rearrangeable and persists in `@AppStorage("sidebarSectionOrder")`. Sidebar uses `.controlSize(.regular)` and `.scrollEdgeEffectStyle(.soft, for: .top)`.
- **Three-column layout** — `NavigationSplitView` with `.navigationSplitViewStyle(.prominentDetail)`. Middle column shows only when a `VirtualFolder` or `Recents` is selected. File hits (search results, orphan rows) skip the middle column and route directly to the editor. Sidebar and middle column resize independently — the editor (detail) absorbs all width changes.
- **Recents** — files-only, cap 50, bucketed `Today` / `Yesterday` / `Previous 7 Days` / `Older` via `Calendar` predicates. Display order is **snapshotted on appear** so tapping a file doesn't jump it to the top mid-interaction.
- **Search** — `.searchable(placement: .sidebar)`. Searches all files (folder-resident and orphan). Filenames first, headings second; matched-range highlighting via `inlinePresentationIntent = .stronglyEmphasized`. Heading parsing is lazy and session-cached in `LibrarySearchCache`. Selecting a heading hit opens the file but does not yet jump to the line.
- **Drag-and-drop** — drag payload strings are prefixed `"folder:UUID"` / `"file:UUID"`. Live reorder via `isTargeted:` callback on `.dropDestination` wrapped in `withAnimation(.snappy)`. Cross-context moves: drop a file onto a folder row → file moves into that folder; drop onto the `Files` section header or any orphan row → file becomes orphan. `.draggable(_:)` without a custom preview so SwiftUI snapshots the source view as the drag image.
- **Sidebar add/move** — empty-space context menu: `New Folder` + `Add Files…`. Folder right-click: `Add Files to [Folder]…`. `Add Files…` from empty context drops files as orphans. New folders insert at order 0 (existing shift +1) with numeric disambiguation on name collision.

## Source-of-truth hierarchy for UI work

Every SwiftUI component, modifier, dimension, or interaction must trace back to one of these — in order:

1. **The SwiftUI `.swiftinterface`** in the macOS 26 SDK:
   `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.4.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface`
   Use `grep -n` for exact signatures, generics, defaults, `@available` annotations. Apple's web docs frequently fail to fetch — fall back here.
2. **Apple SwiftUI documentation** — <https://developer.apple.com/documentation/swiftui>
3. **Apple HIG** — <https://developer.apple.com/design/human-interface-guidelines>
4. **ExploreSwiftUI** — <https://exploreswiftui.com>. Verify against the swiftinterface before shipping.
5. **Shipped macOS apps** (Finder, Mail, Notes, Photos, Settings, Xcode) — when HIG doesn't pixel-spec something, shipped apps are the reference. Screenshots Nathan sends are source of truth.

**Verification rule (non-negotiable):** Before introducing or modifying any SwiftUI component or modifier, read an authoritative source and cite it. Never make a UI decision from memory or assumption. "I think this is how it works" is not acceptable — cite the swiftinterface line number or URL. If the source is unreachable, surface that to Nathan; don't guess.

**Semantic primitives rule:** Don't invent dimensions. Hand-tuned `.frame(width: 22)`, `.font(.system(size: 13))`, ad-hoc paddings, and made-up row heights are not allowed. Use SwiftUI's semantic primitives that scale with `controlSize`, the system Sidebar size setting, and Dynamic Type:

| Want this | Use this | Don't do this |
|---|---|---|
| Bigger icon in a row | `.imageScale(.large)` on the `Label`/`List` | `.frame(width: 22)` on `Image` |
| Bigger icon + text together | `Label` + `.font(.headline)` + `.imageScale(.large)` | `.font(.system(size: 16))` |
| Sidebar size variants | `.controlSize(.small/.regular/.large)` | hand-tuned row paddings |
| Hide section dividers | `.listSectionSeparator(.hidden)` | nested `ScrollView` hacks |
| Detail wins over title | `.layoutPriority(1)` + `.lineLimit(1).truncationMode(.tail)` | manual width math |

- **SF Symbols** — `Image(systemName: "…")`. Browse in `/Applications/SF Symbols.app`.
- **Figma file** (`docs/design/`): layout reference only. Don't pull pixel measurements, fonts, or colors from it into Swift.

## Data model essentials

```swift
@Model final class VirtualFolder { id, name, createdAt, order, files }
@Model final class FileReference { id, lastKnownPath, displayName, addedAt, order, lastOpenedAt, folder }
```

`FileReference` uses plain paths in MVP. v1.1 Iteration A adds `bookmarkData: Data` additively (no destructive migration).

## Things we do NOT do

- Don't write to disk on every edit. Auto-save is OFF in MVP and stays OFF in v1.1.
- Don't invent `// MARK:` comment headers in short files.
- Don't add doc-comments to obvious symbols.
- Don't add error handling for impossible cases — force-unwraps inside controlled `do/catch` are fine.
- Don't add backwards-compat shims — macOS 26 is the only target.
- Don't reach for `.font(.system(size:))` or hand-mixed `Color(red:green:blue:)` — use semantic primitives.
- Don't propose AppKit wraps (`NSViewRepresentable`) in v1.0 — Swift-only until v1.1.
