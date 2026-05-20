### Pommora — Session Handoff

> **Read this first at session start.** Branch + state + next session's priorities here.

#### Current State (end of 2026-05-19 — **v0.2.7.1 NavDropdown SHIPPED**, simplified and cleaned)

**NavDropdown is implemented, simplified, and functional — Nathan signed off.** v0.2.7.1 ships the Liquid Glass dropdown navigation surface (Pinned + Recents tabs, single-click select / double-click open in main detail pane, right-click Pin/Unpin context menu, back/forward arrows, persistent state.json). Build green, **226 unit tests pass** (227 baseline minus 3 deleted EntityRefTests plus 2 new NexusStateTests for backward-compat decode), `swift format lint --strict --recursive` exit 0.

**Versioning quirk:** `v0.2.7.2` is in git history as the first NavDropdown ship attempt (Session 10 first half, end of 2026-05-19). It landed with a standalone preview-window scene + hover-heart favorites + 22 commits of UIX iteration Nathan was unhappy with. The v0.2.7.1 simplification supersedes it. The v0.2.7.2 tag remains in history for archaeological reference; v0.2.7.1 is the canonical NavDropdown ship. The originally-planned v0.2.7.1 Page-editor-touch-ups slot shifts to a later patch number.

**`main` is at the v0.2.7.1 docs commit** (to be tagged + pushed at session close). GitHub CI removed in the same commit (Nathan: failure emails were noise).

##### What shipped in v0.2.7.1 (the simplification + cleanup)

The full feature spec lives at [`// Features//NavDropdown.md`](Features/NavDropdown.md). Headline changes from v0.2.7.2:

- **Standalone preview window machinery removed entirely.** `EntityRef.swift`, `EntityWindowHost.swift`, `EntityRefTests.swift`, and the `WindowGroup(id: "entity", for: EntityRef.self)` scene all deleted. Double-click in the dropdown now routes to the main detail pane via a direct closure from ContentView. A real cross-feature PreviewWindow primitive is a future job (see `Guidelines/CRUD-Patterns.md → Preview-window prerequisite`).
- **Favorites → Pinned, top-to-bottom rename.** Class `FavoritesManager` → `PinnedManager` (file renamed via `git mv`), JSON key `favorites` → `pinned` with backward-compat decode (reads legacy `favorites` as fallback; writes only `pinned`), tab label "Pinned", AppGlobals + ContentView + NavDropdownButton all updated. Two new `NexusStateTests` cover the legacy-key decode and the encoder-doesn't-emit-favorites contract.
- **Hover-heart replaced with right-click Pin/Unpin context menu.** `EntityRow` loses the `isFavorite` / `favoriteAction` params and the entire hover-heart Button. New `isPinned` / `pinAction` params drive a `.contextMenu { Button("Pin Page" | "Unpin Page") { pinAction() } }`. Hover state still tracked, but repurposed to drive a subtle row-background tint (`Color.primary.opacity(0.06)` in a 6pt rounded rect) instead of revealing chrome.
- **Click model: single = select, double = open.** Single-click updates List's native selection chrome (no action). Double-click triggers `.simultaneousGesture(TapGesture(count: 2)) { handleOpen(ref) }` which closes the popover and sets `sidebarSelection`. The `.simultaneousGesture` form is the macOS workaround for SwiftUI List rows where `.onTapGesture(count: 2)` is intercepted by the underlying NSTableView selection handler.
- **Collections wired into `SidebarSelection.init?(stateRef:)`** — leftover `case .collection: return nil` from the v0.2.7.2 "collections not wired" decision is now a real resolver that iterates `vaultManager.vaults.collections(in:)`. `SidebarDetailView` was already routing `.collection` → `CollectionDetailView`, so this single addition makes collection rows openable from the dropdown end-to-end.
- **Routing bypasses `MainWindowRouter` for the dropdown's open path.** `NavDropdownButton` gains an `onOpen: (SidebarSelection) -> Void` closure. `ContentView` constructs it with `{ sel in sidebarSelection = sel }`. The closure writes through SwiftUI's normal @State binding mechanism, which works reliably across view-host boundaries — same root cause as the empty-Recents bug that the snapshot pattern fixes. `MainWindowRouter` stays in place for the back/forward path (different code path, works fine via `bringToFrontTick` observation in ContentView's main view host).
- **Lazy-load fallback for unloaded collections.** When `SidebarSelection(stateRef:)` returns nil for a page (because the host collection hasn't been visited this session — ContentManager loads per-collection lazily per the design), `handleOpen` kicks off a `Task` that walks `vaultManager.vaults` calling `contentMgr.loadAll(for: vault)` + each collection, retrying SidebarSelection construction at each step. SQLite in v0.4.0 makes this O(1) and removes the walk.

##### What shipped in v0.2.7.1 (the additive scope)

- **Page + Item context menus inside Vault and Collection detail views.** Right-click on a Page or Item row in `VaultDetailView` or `CollectionDetailView` opens a menu with **Rename** (alert + TextField, routes to `ContentManager.renamePage` / `renameItem` based on vault-root vs collection parent), **Pin / Unpin {kind}** (toggles `AppGlobals.pinnedManager`), **Delete** (mirrors sidebar's no-confirmation pattern; routes to the right `deletePage` / `deleteItem` overload). `VaultDetailView` uses a `parent(for:)` helper that scans vault-root content first then iterates collections; `CollectionDetailView`'s parent is always the current collection. Collection rows in VaultDetailView intentionally have no context menu — the sidebar's CollectionRow is the canonical surface for collection rename/delete.
- **GitHub CI removed.** `.github/workflows/ci.yml` deleted. Nathan: the workflow doesn't work and just sends failure emails.
- **`Guidelines/CRUD-Patterns.md → Preview-window prerequisite` rule added.** Project-wide constraint: PreviewWindow primitive ships per kind before any "open in preview" UI for that kind is wired. CRUD lands independently. Locks in the lesson from the deleted EntityWindowHost.

##### Future implementation deferred for the dropdown (Nathan-flagged at ship time)

Documented in `Features/NavDropdown.md → Future implementation`. Four items, in order:

1. **Open-in-preview wiring** when the cross-feature PreviewWindow primitive is built for Pages, Vaults, Collections, Spaces, Topics, Sub-topics, Items, and Agenda items.
2. **Fix drag-to-reorder Pinned** — `.onMove` wiring is in place but drag-initiate inside the popover's List doesn't fire end-to-end. Needs investigation; likely a List + popover view-host interaction quirk.
3. **Remove type chip** — drop the trailing "Page / Vault / Topic" text and rely on the leading icon (kind-specific symbol per the project's planned symbol table).
4. **Segmented Pinned/Recents UI polish** — slight opacity / contrast pass on the picker pill.

##### Session 10 commit log (NavDropdown v0.2.7.1 — 8 commits)

| SHA | What |
|---|---|
| `4def823` | v0.2.7.2.1-a.1 — Strip NavDropdown standalone-window machinery (406 lines deleted) |
| `406e585` | v0.2.7.2.1-a.2 — Rename Favorites → Pinned (class, file, JSON key with backward-compat decode) |
| `d524b09` | v0.2.7.2.1-a.3 — EntityRow hover-accent + right-click Pin/Unpin |
| `9c96405` | v0.2.7.2.1-a.4 — Click model: single = select, double = open |
| `3f768cb` | v0.2.7.2.1-b.1 — Page + Item context menus in Vault/Collection detail views |
| `68d497e` | v0.2.7.2.1-a.5 — Fix double-click open: `.simultaneousGesture` + lazy-load fallback |
| `4ad9156` | v0.2.7.2.1-a.6 — Wire collections + bypass MainWindowRouter via direct closure |
| (next) | v0.2.7.1 ship: docs + GitHub CI removal + CRUD preview-window rule |

(The intra-commit version label `v0.2.7.2.1` was used during execution before the final tag decision; the canonical ship tag is **v0.2.7.1**.)

##### What shipped in v0.2.7.0 (Session 9 — prior)

The full editor feature spec lives at [`// Features//PageEditor.md`](Features/PageEditor.md). Headline: native TextKit-2 editor via vendored `swift-markdown-engine` at `External/MarkdownEngine/`, editable title TextField, 300ms debounced save, character-pair auto-pair, auto-unpair on backspace, Apple-AST supplemental styler for BlockQuote / Strikethrough / Table / ThematicBreak, expanded right-click menu, HR-as-real-line. 197/197 tests passed at that ship.

---

#### Next session priorities

Plural, no order decided. Pick based on appetite:

##### (a) Page editor touch-ups *(small, well-scoped)*

Small, well-scoped polish on the shipped editor. Both items are replicable from what Apple Notes / Apple TextEdit ship natively.

- **Blockquote (`>`) rendering** — currently rendered with dimmed text + bg tint + indent via attribute composition (h.8 supplemental styler), but doesn't *look* like Apple Notes. Apple Notes draws a vertical accent bar on the leading edge + heavier bg shading. Implement via the existing `MarkdownTextLayoutFragment.draw` path (add `drawBlockquote(at:in:)` analogous to `drawCodeBlockBackground`). Mark blockquote ranges with a new `.pommoraBlockquote: true` attribute from the supplemental styler.
- **Divider (HR / `---`) rendering** — the line draws but a few rough edges remain:
   - HR auto-transform on typing: typing `---` on its own line should "lock" as an HR; further `-` keystrokes rejected.
   - Visual width / inset: HR currently spans the full text container width. Apple Notes insets to roughly the body text width. Trim by `textInsets.horizontal` in `drawThematicBreak`.
   - Color: confirm `NSColor.separatorColor` at 80% alpha vs swap.
- **Phase 4.5 polish (auto-pair)** — selection-wrap (typing `*` with selected text → `*text*`) + auto-exit-on-whitespace + the 11-test auto-pair test suite still deferred.
- **Phase 3 substantive (engine AST rewrite)** — wholesale-rewrite engine's `MarkdownTokenizer.parseTokens(in:)` body to walk Apple AST + emit `[MarkdownToken]` shims; same for `MarkdownStyler.styleAttributes`; delete `MarkdownTokenizer+Emphasis.swift` + 6 `MarkdownStyler+*` extensions.

##### (b) Sidebar + Vault/Collection drag-to-reorder

Drag Pages between Vault Collections; reorder Spaces / Topics / Sub-topics within their parents; reorder Vaults at the root; reorder Pinned in the NavDropdown (the open follow-up #2 from this session). Uses SwiftUI's `.draggable(_:)` + `.dropDestination(for:)` with custom `Transferable` types per entity kind. Persists order via a new `_order: [<id>]` field on the parent's JSON sidecar (Vault's `_vault.json`, Collection's `_collection.json`, Tier-1 Spaces config). Filesystem reads remain authoritative; the order field is an overlay.

##### (c) v0.3.0 Properties

Full implementation spec at [`// Planning//v0.3.0-Properties-implementation.md`](Planning/v0.3.0-Properties-implementation.md) (14 locked decisions, 4 phases, file:line precision, ~5000 words). Companion uncertainty log at [`// Planning//v0.3.0-Properties-uncertainty-log.md`](Planning/v0.3.0-Properties-uncertainty-log.md). **v0.3.x sub-sequence locked RC-2026-05-19:** .0 Properties / .1 Items pane / .2 Page-wikilinks / .3 SQLite + querying. The v0.3.0 verbatim resume prompt lives at the bottom of the implementation spec — fire that into a fresh session when ready.

##### (d) PreviewWindow primitive

Build the cross-feature standalone-window surface for Pages / Vaults / Collections / Spaces / Topics / Sub-topics / Items / Agenda items. Once any kind has a wired PreviewWindow, the NavDropdown's open-in-preview affordance can be selectively lit up per kind. See `Guidelines/CRUD-Patterns.md → Preview-window prerequisite` for the contract.

---

#### Known follow-up debt (not blocking)

- **NavDropdown Pinned drag-to-reorder** — listed under Future implementation #2 above
- **NavDropdown type chip removal** — listed under Future implementation #3 above
- **NavDropdown segmented picker polish** — listed under Future implementation #4 above
- **In-app Trash window** — `.trash//` data layer shipped v0.2.5; UI surface v0.4.0
- **`// Planning//Page-Editor-Plan.md` Tiptap-locked language** — outdated since v0.2.7 shipped on the swift-markdown path; sync with PageEditor.md or `git rm`
- **`do { try await … } catch { … }` rewrap in SidebarView.swift + IconPickerSheet.swift** — ~12 single-line patterns; cosmetic
- **PommoraWikiLinkResolver** — Pommora-side conforming to engine's `WikiLinkResolver`; v0.3.2 wikilink work depends on this

---

#### Document pointers

- **NavDropdown feature spec**: `.claude/Features/NavDropdown.md` — what shipped at v0.2.7.1 + future implementation
- **Editor feature spec**: `.claude/Features/PageEditor.md` — what shipped at v0.2.7.0 + what's deferred
- **Roadmap**: `.claude/Framework.md`
- **Session history**: `.claude/History.md`
- **Engine vendor docs**: `External/MarkdownEngine/NOTICE.md`
- **Pages data model**: `.claude/Features/Pages.md`
- **Sidebar feature spec**: `.claude/Features/Sidebar.md`
- **Locked specs**: `.claude/Planning/Contexts-Vaults-spec.md`
- **Paradigm-decision registry**: `.claude/Guidelines/Paradigm-Decisions.md`
- **CRUD patterns** (incl. new Preview-window prerequisite): `.claude/Guidelines/CRUD-Patterns.md`
- **Session transcripts**: `.claude/Transcripts/`

---

#### Verbatim resume prompt for next session

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. `main` is at the v0.2.7.1 commit, **`v0.2.7.1` tagged + pushed to origin (NavDropdown SHIPPED, simplified + cleaned)**. 226 unit tests pass; build green; lint exit 0. NavDropdown is functional and signed-off; four follow-up items are tracked in `Features/NavDropdown.md → Future implementation` (preview-window wiring once the primitive exists, drag-to-reorder Pinned fix, type-chip removal, segmented-picker polish). GitHub CI removed. New project-wide rule locked at `Guidelines/CRUD-Patterns.md → Preview-window prerequisite`: PreviewWindow primitive ships per kind before any 'open in preview' UI for that kind is wired. **Possible next priorities** (no order decided): (a) v0.2.7.x Page editor touch-ups — blockquote real chrome + HR auto-lock + divider polish + Phase 4.5 auto-pair polish + Phase 3 engine AST rewrite (see Handoff for spec); (b) Sidebar + Vault/Collection drag-to-reorder (uses SwiftUI .draggable + .dropDestination + per-parent `_order` sidecar field); (c) v0.3.0 Properties (full spec at `.claude/Planning/v0.3.0-Properties-implementation.md` — fire its verbatim resume prompt); (d) PreviewWindow primitive build (unblocks NavDropdown follow-up #1). Branch policy: all commits on `main` directly (Nathan-locked). Every dispatched agent uses Opus 4.7."

---

#### Open questions

- **Brand accent value** — Xcode default stands in; final accent hue at design lock.
- **HighlighterSwift + SwiftMath bridges** — deferred per plan; opt-in later if code-block syntax highlighting + LaTeX rendering become priorities.
- **PreviewWindow design** — what's the shared chrome look? Reuses main toolbar shape, or its own minimal one? Decision deferred until the primitive is built.
