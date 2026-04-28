# Pommora — Project Context

A native macOS markdown and plaintext editor built against the macOS 26 design language. Folder-based (virtual folders containing references to files anywhere on disk), aesthetically aligned with current Apple Design Resources, fully native SwiftUI + AppKit.

The full product spec lives in [`PRD`](../PRD) at the repo root. Read that for problem framing, target user, scope, and milestones. This file is the **operational** context for working in the codebase.

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
├── README.md                           # build, install, contribution
├── .claude/
│   ├── CLAUDE.md                       # this file
│   └── memory/                         # gitignored, project-scoped memory
├── docs/
│   └── design/                         # Figma file, screenshots — personal reference only
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

**Edit Swift in VS Code, run in Xcode.** This is non-negotiable. Nathan strongly prefers to avoid Xcode for editing.

| Task | Where |
|---|---|
| Edit `.swift` files | VS Code (Swift extension by swiftlang) |
| Build (CLI) | `cd Pommora && xcodebuild -scheme Pommora -configuration Debug build` |
| Run / debug | Xcode `Cmd+R` |
| SwiftUI Previews | Xcode (Previews don't render outside it) |
| Edit `Info.plist`, `*.entitlements`, `*.xcassets/Contents.json` | VS Code (text formats) |
| Add a new `.swift` file | Just create it in `Pommora/Pommora/<subdir>/` — synchronized groups pick it up automatically. |
| Adjust target settings, schemes, capabilities | Xcode (rare) |

## Lessons (required reading — never repeat the same mistake twice)

Mistakes I've already made on Pommora live in [`.claude/lessons/`](lessons/) — one file per failure pattern. **Read the relevant file before doing the matching kind of work.** Index: [`.claude/lessons/README.md`](lessons/README.md).

| Before you do this | Read this |
|---|---|
| Any UI change (sizing, fonts, icon scale, padding, row heights, color, materials, drag/drop, animations) | [`lessons/ui-dimensions-and-semantic-primitives.md`](lessons/ui-dimensions-and-semantic-primitives.md) |
| Introducing or modifying any SwiftUI modifier, initializer, or protocol use | [`lessons/swiftui-api-verification.md`](lessons/swiftui-api-verification.md) |

When Nathan flags a new mistake, **append a dated incident** to the matching lesson file, or create a new file (one mistake per file) and link it from `.claude/lessons/README.md` and the table above.

## Memory protocol (project-specific override)

**This project does not use the project-memory subsystem at all.** Every operational rule, feedback correction, and non-obvious preference for Pommora lives in this CLAUDE.md so it is always loaded into context and never skipped. This overrides the global three-tier protocol in `~/.claude/CLAUDE.md` for this repo only.

- Do **not** write to `~/.claude/projects/<proj>/memory/` (the global default).
- Do **not** write to `<project>/.claude/memory/` (a previous Pommora override — now removed).
- If Nathan gives you a feedback rule or non-obvious correction worth keeping, add it to the appropriate section of this file instead of creating a memory entry.

Two-tier ownership rule for Pommora: global preferences in `~/.claude/CLAUDE.md`; everything else — code facts, project state, feedback rules — here.

## Deferred / locked product decisions (in addition to PRD)

These are decisions that constrain future work; they are not yet implemented. Behavior already in code is **not** documented here — read the code.

1. **MVP cut = walking skeleton.** v1.0 ships without rendering toggle, file watching, or security-scoped bookmarks. Those are v1.1 fixup iterations. Plan: `~/.claude/plans/help-me-turn-this-deep-whistle.md`.
2. **Rendering toggle is deferred.** When it returns, it's binary: Raw (mono, plain) / Styled (SF + formatted markdown). The 3-mode design from 2026-04-26 is dropped.
3. **Theme setting** — Settings scene exposes Light / Dark / Device picker (default = Device). App-only override via `.preferredColorScheme(...)`. Stored on `AppState.themePreference`.
4. **Missing files (MVP)** — auto-removed silently on launch. v1.1 (with bookmarks) shifts to inline "Locate…" UX.
5. **Outline panel** — not in MVP. Iteration D of v1.1.
6. **Future view modes** (icon, list, gallery) — deferred. Column view only for now.
7. **`bookmarkData: Data` on `FileReference`** — additive in v1.1 Iteration A. No destructive migration.

## Behavior contracts (already implemented; read code for details)

These describe *what the app does*; the *how* is in the source files.

- **Sidebar** — four top-level sections (`Favorites`, `Folders`, `Files`, `Tags`) plus a `Recents` row at the top. `Favorites` and `Tags` are header-only placeholders. `Folders` lists `VirtualFolder`s as flat rows (no inline file children). `Files` lists *orphan* `FileReference`s (`folder == nil`); cap of 25 before the section becomes internally scrollable. Section order is user-rearrangeable and persists in `@AppStorage("sidebarSectionOrder")`. Sidebar uses `.controlSize(.regular)` and `.scrollEdgeEffectStyle(.soft, for: .top)` so content fades behind the search bar.
- **Three-column layout** — `NavigationSplitView` shows the middle column only when a `VirtualFolder` or `Recents` is selected. File hits (search results, orphan rows) skip the middle column and route directly to the editor.
- **Recents** — files-only, cap 50, bucketed `Today` / `Yesterday` / `Previous 7 Days` / `Older` via `Calendar` predicates. The display order is **snapshotted on appear** so tapping a file (which stamps `lastOpenedAt`) doesn't jump it to the top mid-interaction; new files prepend on next visit.
- **Search** — `.searchable(placement: .sidebar)`. Filenames first, headings second; matched-range highlighting via `inlinePresentationIntent = .stronglyEmphasized`. Filename matches against `titleWithoutExtension` (so the matchedRange aligns with the rendered title). Heading parsing is lazy and session-cached in `LibrarySearchCache`. Selecting a heading hit opens the file but does not yet jump to the line.
- **Drag-and-drop** — drag payload strings are prefixed `"folder:UUID"` / `"file:UUID"` so drops can route by kind. Live reorder happens via the `isTargeted:` callback on `.dropDestination` wrapped in `withAnimation(.snappy)`. Cross-context moves: drop a file row onto a folder row in the sidebar to move the file into that folder; drop onto the `Files` section header (or any orphan row) to make it orphan. `.draggable(_:)` is used **without** a custom preview so SwiftUI snapshots the source view as the drag image (Finder-style).
- **Sidebar add/move** — empty-space context menu shows `New Folder` + `Add Files…`. Folder right-click shows `Add Files to [Folder]…`. `Add Files…` from empty context drops files as orphans (not into a new folder). New folders insert at order 0 (existing folders shift +1) with numeric disambiguation if the name collides.

## Source-of-truth hierarchy for UI work

Every SwiftUI component, modifier, dimension, or interaction must trace back to one of these:

1. **The SwiftUI `.swiftinterface`** in the macOS SDK — the most authoritative source. Path:
   `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.4.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface`
   Use `grep -n` to find exact signatures, generics, defaults, and platform-availability annotations. Apple's web docs are JS-rendered and frequently fail to fetch — fall back to this file when they do.
2. **Apple SwiftUI documentation** — <https://developer.apple.com/documentation/swiftui>. Narrative explanations.
3. **Apple HIG** — <https://developer.apple.com/design/human-interface-guidelines>. Visual correctness (sidebar widths, list row sizes, materials).
4. **ExploreSwiftUI** — <https://exploreswiftui.com>. Fast lookup catalog. Verify against the swiftinterface before shipping.
5. **Shipped macOS apps** (Finder, Mail, Notes, Photos, Settings, Xcode) — when the HIG doesn't pixel-spec something, the canonical macOS apps *are* the reference. Screenshots from these are source of truth.

**Rule (verification, non-negotiable):** Before introducing or modifying any SwiftUI component, modifier, or interaction pattern, read the relevant official source. NEVER make a UI decision based on memory or assumption. If the source is unreachable, surface that to Nathan rather than guessing. "I think this is how it works" is not acceptable; cite the file (with line number, e.g. `grep -n "func draggable" …swiftinterface`) or URL you read. If Apple's HIG doesn't specify exact dimensions for what you're building, say so explicitly and don't reach for a component or principle without direct evidence of correct use. Screenshots Nathan sends from Finder/Mail/Notes/Photos/Settings/Xcode are source of truth — name the SwiftUI primitive you're matching them with.

**Rule (semantic primitives):** Don't invent dimensions. Hand-tuned `.frame(width: 22)`, `.font(.system(size: 13))`, ad-hoc paddings, and made-up row heights are not allowed. Use SwiftUI's *semantic* primitives that scale with `controlSize`, the system Sidebar size setting, and Dynamic Type:

| Want this | Use this | Don't do this |
|---|---|---|
| Bigger icon in a row | `.imageScale(.large)` on the `Label`/`List` | `.frame(width: 22)` on `Image` |
| Bigger icon + text together | `Label` + `.font(.headline)` + `.imageScale(.large)` | `.font(.system(size: 16))` |
| Sidebar size variants | `.controlSize(.small/.regular/.large)` (per HIG Sidebars) | hand-tuned row paddings |
| Hide section dividers in a `List` | `.listSectionSeparator(.hidden)` | nested `ScrollView` hacks |
| Detail wins over title in a row | `.layoutPriority(1)` on detail + `.lineLimit(1).truncationMode(.tail)` on title | manual width math |

**Why this matters (do not forget):** Past pattern — when I jumped to custom dimensions (`.frame(width: 22, alignment: .center)`, `.font(.title3)` on an icon, hand-rolled `HStack`s instead of `Label`), Nathan correctly flagged that I was "making up what I don't know about design principles." Apple's semantic modifiers automatically scale across `.controlSize`, the system Sidebar size setting, and Dynamic Type. Hand-tuned values silently break those. This rule covers *dimensions and visual values*, not just modifier names.

- **SF Symbols** — `Image(systemName: "…")`. Browse in `/Applications/SF Symbols.app`.
- **Figma file** (`docs/design/`): layout reference only. Don't pull pixel measurements, fonts, or colors from it into Swift.
- **App icon**: deferred.

## Data model essentials

```swift
@Model final class VirtualFolder { id, name, createdAt, order, files }
@Model final class FileReference { id, lastKnownPath, displayName, addedAt, order, lastOpenedAt, folder }
```

`FileReference` uses plain paths in MVP. v1.1 Iteration A adds `bookmarkData: Data` additively (no destructive migration).

## Things we do NOT do

- Don't write to disk on every edit. Auto-save is OFF by default in MVP and remains OFF by default in v1.1.
- Don't invent comment headers (`// MARK:` is fine when it actually segments long files; don't sprinkle them in short ones).
- Don't add doc-comments to obvious symbols. SwiftUI views with self-explanatory names don't need `///` summaries.
- Don't add error handling for impossible cases (force-unwraps inside `do/catch` we already control are fine).
- Don't add backwards-compat shims — macOS 26 is the only target.
- Don't reintroduce a tokens file or hand-translated design values. SwiftUI's semantic styles, SF Symbols, and `NSColor.systemX` are the source of truth. If you find yourself reaching for `.font(.system(size:))` or `Color(nsColor: .somethingBackgroundColor)`, stop and use the semantic primitive instead.
