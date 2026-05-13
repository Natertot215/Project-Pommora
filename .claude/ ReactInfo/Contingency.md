### React Contingency Methodology

Translation patterns for converting Swift-first Pommora work back to React+Electron if a future pivot is ever undertaken. **This document is methodology only — not decision criteria.** The stack decision is locked at SwiftUI; this file exists so React-translation patterns stay legible alongside Swift work.

#### Update obligation

When meaningful Swift implementation work lands — anything beyond a small change, or anything that has an obvious React-side equivalent worth recording — add a paired note in the relevant `// ReactInfo// <topic>.md` file. Skip for trivial Swift work where the React equivalent is uninteresting or already covered. Judgment call, not mandatory pairing.

The trigger phrase is "something big OR an obvious React way" — if either applies, log it.

#### Translation patterns

##### Editor surface
- Swift Option 2 (WKWebView + JS editor) → React: same JS editor, no WebView wrapper, mounted directly. Most of the editor code transfers verbatim because the JS layer is shared.
- Swift Option 1 (native NSTextView with attribute-based decorations) → React: doesn't translate — start from BlockNote or Tiptap node specs. See `Editor.md`.

##### State + reactivity
- `@Observable` Swift classes → Zustand vanilla stores with `useSyncExternalStore` bindings. The structural shape (services in DI, view state separate) maps cleanly.
- GRDB `ValueObservation.tracking { ... }.values(in:)` → hand-rolled pub/sub keyed by SQLite table names + better-sqlite3 mutations. See `StateData.md`.

##### Drag-and-drop (Spaces)
- `visfitness/reorderable` + `stevengharris/SplitView` + `Codable Block` enum → `@dnd-kit/core` v6 + flat-array `[id, depth, parentId]` tree. See `Spaces-DnD.md`.

##### File watching
- FSEventStream (EonilFSEvents) → `@parcel/watcher` v2.5+. Same APFS / atomic-rename gotchas on both. Same debounce + outbound-mtime-tracking logic.

##### Design tokens
- SwiftUI `Color` / `Font` extensions → CSS custom properties (`--surface-primary-bg`). Same Figma source exports both; only the export target file changes. See `Styling-Tokens.md`.

##### Icons
- SF Symbols via `Image(systemName:)` (no indirection needed) → Material Symbols via `react-material-symbols` through `.pommora// symbols.json` semantic-role layer. See `Symbols-guide.md`.

##### Distribution
- Sparkle 2.x → electron-updater (GitHub Releases path of least resistance). Code-signing + notarization patterns are documented per stack; sandboxing constraints are identical. See `Distribution.md`.

##### Mac OS integration
- SwiftUI: every integration (QuickLook, CoreSpotlight, Share Extension, NSServices, Finder file-promise) is first-party.
- React: hard ceilings on QuickLook (companion bundle), Share Extension (impossible), CoreSpotlight (electron-spotlight, fragile), Finder file-promise (broken). See `MacIntegration.md`.

#### Skill drift note

Continuing Swift work without direct React exposure does not freeze React capability — general programming intuition (state management, drag-and-drop algorithmic shape, file-watcher debouncing, FTS query design, atomic-write discipline) transfers. If a pivot ever happens, the Swift months count as relevant practice even though they were not React-flavored.