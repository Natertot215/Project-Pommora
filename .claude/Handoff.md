### Pommora — Session Handoff

#### Current State

**v0.1a Nexus Foundation shipped on SwiftUI / macOS Tahoe (26.4).** Sandboxed picker, security-scoped bookmark persistence, `.nexus/` initialization, sidebar mirroring the user-picked nexus folder. Manually verified end-to-end — picker, init flow, sidebar tree filtering, persistent bookmarks, vault rename recovery.

15 commits on `main` since v0.0. Implementation lives at [Pommora/Pommora/Nexus/](Pommora/Pommora/Nexus/) (7 files: `Nexus`, `NexusManager`, `NexusBookmark`, `NexusStore`, `NexusIdentity`, `AppState`, `ULID`, `FolderTree`) and [Pommora/Pommora/Sidebar/](Pommora/Pommora/Sidebar/) (3 files: `SidebarView`, `SidebarRow`, `SidebarNode`). 25 unit tests pass. Design + Findings preserved at [.claude/Planning/v0.1-nexus-foundation-design.md](.claude/Planning/v0.1-nexus-foundation-design.md).

The placeholder sidebar rows from v0.0 have been replaced. The `NSSearchField` anchored via `.safeAreaInset(.top)` and the inspector toggle wrapped in `withAnimation(.smooth(duration: 0.30))` are preserved unchanged.

---

#### Next Session — Discussion Items

Two threads remain after the foundation, plus an adjacent symbol-registry decision parked from before.

1. **Standard-symbol convention / registry.** Every sidebar row currently uses placeholder SF Symbols (`folder` / `doc.text` / `list.bullet.rectangle`) hardcoded in `SidebarRow.swift`. Nathan wants a stable registry — "for X type of entity, use Y SF Symbol" — so symbols become semantic without per-row specification. Open shape: JSON lookup file? Swift extensions (e.g., `Symbol.pageIcon`, `Symbol.collectionIcon`)? Markdown reference table? Decide format, populate mapping for Spaces / Collections / Items / Pages / loose entities, swap out the placeholders in `SidebarRow.swift`. React-side semantic-role pattern at `// ReactInfo// Symbols-guide.md` could inform the Swift shape.

2. **v0.1b — Tab integration.** Sidebar entries are currently selectable but click does nothing. Wire up: clicking a `.md` row opens it as a tab in the top-bar tab strip; main pane shows raw markdown. Standard `+` / `×` / `⌘T` / `⌘W` / `⌘1..9` chrome per [Features/Navigation-Bar.md](Features/Navigation-Bar.md). Open tabs + active tab persist via `.nexus/state.json` inside the nexus (per the v0.1a state-file separation).

3. **v0.1a UX polish (deferred per direction).** All UI copy is functional/minimal — no welcome states, no error alerts, no descriptive panel text. Design pass picks these up. Specifically: empty-nexus state in the sidebar; first-launch picker-canceled empty state; error display surface for `NexusManager.pendingError`.

---

#### Pending Explorations

- **Audit findings to commit or defer** — Zod-equivalent validation + atomic writes + ULID per block, FTS5 `unicode61` mode, journal files for crash safety. Captured as findings, not committed. Decide once v0.2 (SQLite + watcher) implementation begins.

- **Optional spike before editor commit** — fork-Clearly assessment to size the native build gap (Option 1), or a WKWebView-host JS editor PoC (Option 2). Option 2 is well-documented via MarkEdit as the production reference; the `file://` ES-module block + `WKURLSchemeHandler` workaround is Apple-documented (see `// Features//Pages.md`). React-side reference at `// ReactInfo// Editor.md`.

- **Sidebar inline-chevron experiment (Finder pattern).** Spiked during v0.0 polish: dropping `DisclosureGroup` for Collections and hand-rolling chevron + member ForEach gives flush-left flat rows. Reverted to `DisclosureGroup` for the v0.0 baseline (Apple-default Mail/Xcode pattern). Revisit with v0.1+ content — Nathan wants tighter chevron-to-icon spacing than Apple's default, with the rest of the sidebar visually matching. Full note → `// Features//Sidebar.md`.

- **Sidebar selection language not built.** Sidebar.md documents intent (subtle gray fill + accent foreground, Mail-style). v0.0 ships with macOS-default sidebar selection (accent-blue fill + white foreground) because `.tint(_:)` doesn't propagate to NSTableView's source-list selection on macOS 26 Tahoe, and the AppKit introspection workaround was judged out of scope for v0.0. Revisit when content lands and the visual cost of bright-accent selection becomes concrete.

---

#### Known Spec Gaps

Real items needing resolution before they bite, organized by when they'll surface.

##### Implementation risk

- **Editor risk — substantially de-risked.** Two editor options documented in `// Features//Pages.md`: (1) native Swift editor — fork Clearly or build original on NSTextView/AppKit (source-with-decorations, fully native); (2) WKWebView hosting Tiptap, Milkdown, or BlockNote — likely direction; all three have solid Markdown translation; native SwiftUI shell wraps the editor canvas. A bounded spike (WKWebView-host JS editor PoC, or fork-Clearly assessment for the native path) would de-risk specifics before committing. React-side reference at `// ReactInfo// Editor.md`.

- **`nexus.db` location** — *resolved in v0.1a.* SQLite index lives at `~//Library//Application Support//com.nathantaichman.Pommora//nexuses//<nexus-id>//nexus.db` per Apple Foundation + GRDB.swift recommendation. Per-nexus subdir keyed by ULID survives nexus rename/move; marked `isExcludedFromBackupKey` for iCloud-Backup quota hygiene. The nexus folder stays purely canonical content.

##### Framework version ordering (surfaces v0.6–v0.8)

- **v0.6 reads `_collection.json` before v0.8 introduces Collections.** Likely reorder: v0.6 (Collections: typed, schema, basic views) → v0.7 (Properties: simple) → v0.8 (Properties: rich) → v0.9 (more views).
- **Sidebar shape changes mid-flight.** v0.1 mirrors folder structure; v0.8 shifts to the three-heading logical model. Either the logical sidebar lands earlier with stub Collection support, or the v0.1 sidebar is throwaway scaffolding.

##### SQLite / indexing

- **`links` table doesn't capture Space outlinks.** `from_kind` is currently `'page' | 'item'`; Spaces' widget blocks reference Collections / Pages / Items by ID without going into the index. Either expand `from_kind` to include `'space'` or document the limitation.
- **Pages lack `created_at` in frontmatter** (Items have it). Filesystem `mtime` gets clobbered by iCloud / git sync. Pages should have `created_at` in frontmatter for parity.

##### Underspecified UX edges

- **Filename collisions on creation** — auto-suffix (`Notes 2.md`)? Reject? Prompt? Wikilink-resolution collisions have rules; creation-time collisions don't.
- **Pommora-flavored Markdown is a dialect** — the `:::columns` and `:::callout` directives appear as inert notation in non-Pommora tools. Standard Markdown round-trips perfectly; the directives don't. Worth acknowledging this honestly in the docs rather than implying universal portability.
- **First-launch with an existing folder** — *resolved in v0.1a.* `.nexus/` already present → load existing `nexus.json`, skip init. Empty folder → silent init. Non-empty folder without `.nexus/` → confirm dialog before init.
- **`@view` language in Spaces is imprecise** — docs use "`@view` directive" but `.space.json` is structured JSON with `embedded-collection-view` blocks. Either formalize a directive grammar or change the language to "embedded-view blocks."

---

#### Branch Status

`main`. v0.1a foundation work landed across 15 commits since v0.0; latest is the post-implementation doc sync. Studio working tree is the current source of truth.

#### Open Questions

- **Brand accent value.** Xcode default stands in for v0.0; final accent hue picked at design lock (not v0.0-blocking).
- **Editor option 1 vs option 2.** v0.3+ decision; doesn't affect v0.0.
