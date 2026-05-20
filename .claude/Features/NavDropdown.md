### Nav Dropdown

Pommora's primary navigation-history surface — a **Liquid Glass dropdown button** in the trailing edge of the toolbar that opens a **popover panel** containing two toggleable lists: **Pinned** (user-curated, right-click to pin) and **Recents** (auto-tracked). Replaces the horizontal tab strip from the v0.0–v0.2.6 era and consolidates navigation chrome into a single always-visible control.

![NavDropdown visual reference](assets/NavDropdown-mockup.png)

**Status: SHIPPED at v0.2.7.1 (end of 2026-05-19).** Functional layer + click model + context-menu Pin + detail-view context menus all working. 226 unit tests pass; build green; lint exit 0.

> **Version note:** v0.2.7.2 was the first NavDropdown ship attempt (Session 10 first half of 2026-05-19) — it landed with a standalone-window preview surface + hover-heart favorites + 22 commits of UIX iteration Nathan was unhappy with. The v0.2.7.1 simplification (Session 10 second half) supersedes it: standalone windows removed (deferred to a real PreviewWindow primitive), hover-heart replaced with right-click Pin context menu, Favorites renamed Pinned throughout, single = select / double = open semantics, plus detail-view context menus on Page + Item rows. The v0.2.7.2 tag stays in git history; v0.2.7.1 is the canonical shipped NavDropdown.

---

#### Future implementation (deferred from v0.2.7.1)

Captured at ship time; the functional layer is done but these refinements are explicit follow-ups:

1. **Open-in-preview wiring** — when the cross-feature PreviewWindow primitive is built for Pages, Vaults, Collections, Spaces, Topics, Sub-topics, Items, and Agenda items, light up the dropdown's preview-on-click affordance. **Until that primitive exists, no "open in standalone window" UI ships here** — single/double-click both route to the main detail pane (and Items route to the existing ItemWindow). See `Guidelines/CRUD-Patterns.md → Preview-window prerequisite` for the project-wide rule.
2. **Drag-to-reorder Pinned** — currently doesn't work end-to-end (the `.onMove` wiring is in place but the drag doesn't initiate properly inside the popover's List). Needs investigation. Likely a SwiftUI List + popover view-host interaction issue.
3. **Remove type chip** — drop the trailing "Page / Vault / Topic" chip text and rely on the leading icon (kind-specific symbol per the project's planned symbol table) for type identification. Cleaner rows; fewer redundant labels.
4. **Segmented Pinned/Recents UI polish** — slight opacity / contrast pass on the picker pill. Not blocking; visual nit.

##### Possible scope cuts (under consideration)

The current dropdown can hold any entity kind. Nathan may decide to **drop Spaces, Topics, Sub-topics, Vaults, and Collections** from Recents + Pinned in favor of only **Pages, Items, and Tasks (Agenda)** — the "things you're actively working on" entities, not the organizational scaffolding. This would simplify the dropdown to a working-set view rather than a universal navigator. Decision deferred; if locked, the data layer (EntityStateRef.Kind) stays unchanged but `RecentsManager.record` + `PinnedManager.toggle` would gate by kind, and the entity roster table above contracts accordingly.

---

#### Toolbar layout

```
LEFT                                                       RIGHT
[ ◯◯◯ ] [≡] [‹] [›] ····· [▦ NavDropdown │ ▢ Inspector]
 traffic  sidebar back/fwd     square.on.square  sidebar.trailing
 lights   toggle  through      ────── glass pill (segmented) ──────
                  Recents
```

Left to right:

- **Traffic lights** — OS window controls
- **Sidebar toggle (`≡`)** — system-provided by `NavigationSplitView`
- **Back / Forward (`‹ ›`)** — walks the Recents cursor (older / newer). `⌘[` / `⌘]` are the keyboard partners. Stepping does NOT modify Recents order.
- (centre, empty) — no tab strip
- **NavDropdown trigger (`square.on.square`)** + **Inspector toggle (`▢`)** — render as a single Liquid Glass pill, two segments, divider between them.

Window title is suppressed (`.windowToolbarStyle(.unified(showsTitle: false))`).

---

#### Trigger button

| Spec | Value |
|---|---|
| SF Symbol | `square.on.square` |
| Style | Plain segment inside a shared `.glassEffect()` pill (paired with the inspector toggle); standalone callers can pass `asSegment: false` to render as a solo Liquid Glass capsule |
| Placement | `ToolbarItem(placement: .primaryAction)`, trailing-right, paired with the inspector toggle |
| Keyboard | `⌘T` opens the panel |
| Activation | Single click or `⌘T`; opens `.popover(isPresented:arrowEdge:)` attached to the button |

---

#### Panel structure

```
┌─────────────────────────────────────────┐
│   [ Pinned │ Recents ]                  │  ← segmented picker
├─────────────────────────────────────────┤
│  ▦  Stoic Reflections          Page    │
│  📖 Reading List               Vault    │
│  🎨 Studio                     Space    │
│  ▦  Q3 Plan                    Page    │
│  ▦  Meeting Notes              Page    │
│  📚 Productivity               Topic    │
│  …                                      │
└─────────────────────────────────────────┘
```

- Width: 320pt (fixed via `.frame(width: 320)`)
- Height: `minHeight: 300, maxHeight: 400`
- **Segmented picker** at top with "Pinned" and "Recents" tabs (`PanelMode.pinned` is the default landing tab)
- **Row separators**: hairline (`.listRowSeparator(.visible)`) between each row
- **Reference**: `assets/NavDropdown-mockup.png` (dark-mode Figma export, locked 2026-05-19; visual polish in #4 of "Future implementation")

Scrolling the list does NOT expand the panel; the panel is a fixed envelope around a scrollable list.

##### Snapshot pattern (load-bearing)

The Pinned and Recents lists render from `@State pinnedSnapshot` / `recentsSnapshot` arrays that refresh on `.onChange(of: isPresented)` + after pin/unpin mutations. Direct `@Environment(PinnedManager.self)` access through the popover's view host doesn't propagate `@Observable` mutations reliably — the snapshot indirection bypasses that edge case. **Don't unilaterally remove it.**

---

#### Row anatomy

```
[icon] [title — truncates with ellipsis] [type chip]
```

- **Icon** — entity's symbol (Page = `doc.text`, Vault = `book`, Space = `rectangle.3.group`, Topic / Sub-topic = `folder`, Item = `tray`, Collection = `tray.2`, Agenda = `calendar`)
- **Title** — `Text(ref.title).lineLimit(1).truncationMode(.tail)`
- **Type chip** — full-word, `.font(.caption)`, `.foregroundStyle(.secondary)`, trailing

**Hover accent:** the row background tints to `Color.primary.opacity(0.06)` in a 6pt rounded rect when hovered. No revealed chrome — the row's only affordance on hover is the tint.

**Single-click** — highlights the row via List's native selection chrome. No action fires.

**Double-click** — triggers `.simultaneousGesture(TapGesture(count: 2))` (the `.simultaneousGesture` form is the macOS workaround for SwiftUI List rows where `.onTapGesture(count: 2)` is intercepted by NSTableView's selection handler). Closes the popover and routes to the open path (see "Open flow" below).

**Right-click** — opens a `.contextMenu` with a single `Button(isPinned ? "Unpin {chip}" : "Pin {chip}")`. Toggles `AppGlobals.pinnedManager?.toggle(ref)` + refreshes snapshots.

---

#### Open flow

When a row is double-clicked, `handleOpen(ref)` dispatches based on `ref.typedKind`:

- **`.page` / `.vault` / `.space` / `.topic` / `.subtopic` / `.collection`** — closes the popover, calls `onOpen(sel)` with a `SidebarSelection` built via `SidebarSelection.init?(stateRef:)`. ContentView's `onOpen` closure writes directly to its `sidebarSelection` `@State`. The main detail pane swaps to render the selected entity, overriding whatever was open.
- **`.item`** — closes the popover, looks up the Item via `ContentManager.items(in: vault/collection)` (brute-force walk; SQLite in v0.4.0 makes it O(1)), and calls `AppGlobals.presentItemAction?(item)` to open the existing `ItemWindow` popover.
- **`.agenda` / `.none`** — no-op for now. Agenda surfaces ship at v0.6.0.

##### Routing architecture

NavDropdownButton takes an `onOpen: (SidebarSelection) -> Void` closure at construction. ContentView passes `{ sel in sidebarSelection = sel }`. The closure captures ContentView's `@State` write path, so writes propagate via SwiftUI's normal binding mechanism — reliable across view-host boundaries.

**Why not MainWindowRouter for the dropdown's open path?** `MainWindowRouter` is `@Observable` and lives in `AppGlobals`. Writing through it from the popover view host doesn't trigger ContentView's `.onChange` reliably — same root cause as the snapshot pattern. The dropdown bypasses the router; `MainWindowRouter` remains in place for the back/forward path (driven by `BackForwardButtons` from the main toolbar view host, where `.onChange(of: mainWindowRouter?.bringToFrontTick)` does fire reliably).

##### Lazy-load fallback

If `SidebarSelection.init?(stateRef:)` returns nil for a page or collection (because the host vault's content hasn't been loaded this session — `ContentManager` lazy-loads per-collection on detail-view appear), `handleOpen` falls back to an async walk of `vaultManager.vaults` calling `contentMgr.loadAll(for: vault)` + each collection, retrying SidebarSelection construction at each step. Eventually finds the entity and routes. SQLite in v0.4.0 makes this O(1) and removes the walk.

##### Standalone preview windows — deferred

The v0.2.7.2 first-attempt added a `WindowGroup(id: "entity", for: EntityRef.self)` scene + `EntityWindowHost` that spawned a separate macOS window for full-frame entities, with an Expand button to commit to the main pane. All of that was deleted in v0.2.7.1. A real **PreviewWindow primitive** is the future home for "open in preview" — when it lands, the NavDropdown can selectively light up preview-on-click per kind. See `Guidelines/CRUD-Patterns.md → Preview-window prerequisite` for the project-wide contract.

---

#### Recents rules

| Spec | Value |
|---|---|
| Storage cap | **500** (single source of truth in `RecentsManager`) |
| Dropdown display cap | **100** (top 100 from store) |
| Sidebar full-frame view cap (v0.6.0+) | **500** (full store) |
| Eviction | LRU — oldest drops when cap hit |
| Dedupe | Re-inserting an existing entity moves it to position 0, doesn't duplicate |

**Trigger to bump to position 0:**

1. **Sidebar click** → entity lands in main detail pane → `ContentView.onChange(of: sidebarSelection)` records to Recents (unless `RecentsManager.isNavigatingHistory == true`)
2. **Dropdown double-click** → entity opens in main detail pane via `sidebarSelection = sel` → the same `onChange(of: sidebarSelection)` records
3. **Item click anywhere** → `ItemWindow.onAppear` records

The `isNavigatingHistory` flag is set true during back/forward stepping so cursor movement doesn't re-record the older entity (which would reset cursor to 0 and break LRU order).

---

#### Pinned rules

- **Uncapped, insertion-ordered** — drag-to-reorder is wired (`.onMove(perform:)` → `PinnedManager.move(fromOffsets:toOffset:)`) but currently doesn't fire end-to-end inside the popover; see Future implementation #2.
- **Single entry point**: right-click any row in the dropdown (Pinned tab OR Recents tab) → context menu → "Pin {kind}". Also mirrored in `VaultDetailView` and `CollectionDetailView` context menus on Page + Item rows.
- **Separate Codable array** — NOT a flag on Recents entries. An entry falling off the Recents cap does not un-pin itself.
- **Open flow identical to Recents** — single-click highlights, double-click routes to main detail pane (or ItemWindow for Items).
- **Removal**: right-click a row in the Pinned tab → "Unpin {kind}" → entity removed from Pinned (stays in Recents if still within cap).

---

#### Entity roster + chip text

| Entity kind | Chip text | Recents trigger | Openable from dropdown? |
|---|---|---|---|
| Page | "Page" | main-frame land | ✓ |
| Vault | "Vault" | main-frame land | ✓ |
| Collection | "Collection" | main-frame land (via `.collection(c)` SidebarSelection) | ✓ |
| Space | "Space" | main-frame land | ✓ |
| Topic | "Topic" | main-frame land | ✓ |
| Sub-topic | "Sub-topic" | main-frame land | ✓ |
| Item | "Item" | popover open (`ItemWindow`) | ✓ |
| Agenda | **"Task"** | (TBD at v0.6.0) | ✗ — v0.6.0+ |
| Homepage | — | excluded | never |

"Task" is a chip-label override for Agenda items (underlying entity stays `.agenda.json`; the chip just reads "Task").

---

#### Back / Forward arrows

- Position: trailing-left in the toolbar (`ToolbarItemGroup(placement: .navigation)`), inside a `.glassEffect()` pill
- `‹` (back) — moves the active cursor one step DEEPER into the Recents list (older entity becomes active in the main detail pane)
- `›` (forward) — opposite direction (newer entity)
- Keyboard partners: `⌘[` and `⌘]` (Safari / Finder / Xcode convention)
- Stepping through Recents does NOT modify the Recents order — the cursor is a separate concept from the LRU position. `MainWindowRouter.requestStep(to:)` sets `pendingIntent = .stepHistory`; ContentView's `onChange(of: bringToFrontTick)` skips the record() call when intent is `.stepHistory`.
- Disabled states: `‹` disabled when at the deepest end; `›` disabled when at position 0

---

#### Persistence

**File:** `<nexus>/.nexus/state.json` — per-nexus, vault-portable. The existing machine-level `~/Library/Application Support/Pommora/state.json` (managed by `AppState`) is unaffected — these are two separate files for two different layers (machine-global vs per-nexus).

**Codable shape:**

```json
{
  "schemaVersion": 1,
  "recents": [
    { "kind": "page", "id": "01HF...", "title": "Stoic Reflections" },
    { "kind": "vault", "id": "01HG...", "title": "Reading List" }
  ],
  "pinned": [
    { "kind": "page", "id": "01HF...", "title": "Stoic Reflections" }
  ],
  "cursor": 0
}
```

**`EntityStateRef` fields:**

- `kind` — raw String, mapped to `Kind` enum: `page` / `vault` / `collection` / `space` / `topic` / `subtopic` / `item` / `agenda`. Raw String allows forward-compat with future kinds.
- `id` — ULID of the underlying entity (rename-safe)
- `title` — denormalized, refreshed on resolve. Used for orphan display when the entity has been deleted on disk
- `cursor` (top-level) — current position in Recents for back/forward arrows; 0 = newest active

**Equality / hash** by `(kind, id)` so a renamed entity stays the same record.

**Atomic-write contract** — same pattern as existing managers (`SavedConfigManager`, `AppState`). `AtomicJSON.write` uses `Data.write(to:options:.atomic)` which writes to a temp file + atomic rename.

##### Backward-compat: `favorites` → `pinned` key rename

The JSON key was renamed from `favorites` to `pinned` at v0.2.7.1 along with the class rename. `NexusState.CodingKeys` defines both `case pinned` and `case favoritesLegacy = "favorites"`. The decoder reads `pinned` first, falls back to `favoritesLegacy` if absent. The encoder only writes `pinned`, so the legacy key disappears on first save. Two `NexusStateTests` cover this contract:

- `decodesLegacyFavoritesKey()` — feeds JSON containing `"favorites": [...]` + verifies it lands in `pinned`
- `encoderWritesOnlyPinnedKey()` — round-trips a `NexusState` and verifies the output JSON contains `"pinned"` but NOT `"favorites"`

---

#### Saved (sidebar) ≠ Pinned (dropdown)

These are **distinct classifications**, not redundant:

| Concept | Surface | Data | Trigger |
|---|---|---|---|
| **Saved** (sidebar) | `Saved` section in sidebar — fixed-three pins | `SavedConfig` (existing, `.nexus/saved-config.json`) | System-defined (Homepage / Calendar / Recents) |
| **Pinned** (dropdown) | Pinned tab in dropdown panel | `PinnedManager` (`.nexus/state.json`) | User right-clicks rows in dropdown OR right-clicks Page/Item rows in Vault/Collection detail views |
| **Recents** (dropdown) | Recents tab in dropdown panel | `RecentsManager` (`.nexus/state.json`) | Auto — main-frame land or `ItemWindow.onAppear` |
| **Recents** (sidebar full-frame view) | Saved-section `Recents` pin → full-frame view at v0.6.0 | Same data as dropdown Recents | n/a — read-only view of the same store |

The sidebar `Recents` pin and the dropdown Recents share the same underlying `RecentsManager` store but render different surfaces — dropdown shows top 100 quickly; sidebar full-frame view at v0.6.0 shows up to 500 with sort + filter.

---

#### Detail-view context menus (v0.2.7.1 additive scope)

Right-click on a Page or Item row inside `VaultDetailView` or `CollectionDetailView` opens a `.contextMenu` with three items:

- **Rename** — opens an `.alert("Rename", isPresented:)` containing a `TextField` + Rename / Cancel buttons. Commits via `ContentManager.renamePage(_:to:in:vault:)` / `renameItem` (collection-hosted) or `renamePage(_:to:inVaultRoot:)` / `renameItem(_:to:inVaultRoot:)` (vault-root).
- **Pin / Unpin {kind}** — toggles `AppGlobals.pinnedManager?.toggle(ref)`. The menu label reads "Pin Page" / "Unpin Page" / etc. depending on current pin state and row kind.
- **Delete** — destructive role. Mirrors the sidebar's no-confirmation pattern (the sidebar's PageRow / SubtopicRow context menus do the same). Routes to `ContentManager.deletePage(_:in:)` / `deletePage(_:inVaultRoot:)` / `deleteItem` overload based on parent.

VaultDetailView uses a `parent(for: DetailRow) -> PageParent?` helper that scans `contentManager.pages(in: vault)` / `items(in: vault)` first for a vault-root match, then iterates `vaultManager.collections(in: vault)`. O(N × M); fine for v0.2.7.1 (SQLite in v0.4.0 makes it O(1)).

CollectionDetailView's parent is always `.collection(collection, vault: vault)` — no lookup needed.

Collection rows in VaultDetailView intentionally have NO context menu — sidebar's `CollectionRow` is the canonical surface for collection rename/delete.

---

#### Type architecture

##### `EntityStateRef`

Flat Codable wire-record for state.json. `Hashable, Sendable, Codable`. Equality by `(kind, id)`. Defined in `Pommora/Pommora/NavDropdown/EntityStateRef.swift`.

##### `NexusState`

Top-level Codable container for state.json. Holds `recents`, `pinned`, `cursor`, `schemaVersion`. Custom Codable for backward-compat key fallback. Defined in `Pommora/Pommora/NavDropdown/NexusState.swift`.

##### `RecentsManager`

`@MainActor @Observable`. Holds `entries`, `cursor`, `isNavigatingHistory`. Provides `record(_:)`, `stepBack()`, `stepForward()`, `canStepBack`, `canStepForward`, `dropdownTop`, `load()`, `save()`. Defined in `Pommora/Pommora/NavDropdown/RecentsManager.swift`.

##### `PinnedManager`

`@MainActor @Observable`. Holds `entries`. Provides `contains(_:)`, `toggle(_:)`, `move(fromOffsets:toOffset:)`, `load()`, `save()`. Defined in `Pommora/Pommora/NavDropdown/PinnedManager.swift`.

##### `MainWindowRouter`

`@MainActor @Observable` bridge for back/forward stepping. `Intent` enum (`.directNavigation` / `.stepHistory`). `requestOpen(to:)` / `requestStep(to:)`. The dropdown's open path bypasses this (uses direct closure from ContentView); only BackForwardButtons + ContentView's `onChange(of: bringToFrontTick)` handler use it. Defined in `Pommora/Pommora/NavDropdown/MainWindowRouter.swift`.

##### `SidebarSelection.init?(stateRef:)`

Bridges `EntityStateRef` → `SidebarSelection` by looking up via `AppGlobals` managers. Returns nil for kinds that aren't main-detail-pane targets (`.item`, `.agenda`) and for entities that no longer exist on disk. Defined in `Pommora/Pommora/Sidebar/SidebarSelection.swift`.

##### `EntityRow`

The single row view used in both Pinned and Recents lists. Takes `ref: EntityStateRef`, `isPinned: Bool`, `pinAction: () -> Void`. Renders icon + title + chip + hover-tint background + `.contextMenu` with "Pin {chip}" / "Unpin {chip}". Defined in `Pommora/Pommora/NavDropdown/EntityRow.swift`.

##### `NavDropdownButton`

The toolbar trigger + popover panel. Takes `asSegment: Bool` (default `false`) and `onOpen: (SidebarSelection) -> Void`. Owns the snapshot state. Defined in `Pommora/Pommora/NavDropdown/NavDropdownButton.swift`.

##### `BackForwardButtons`

The `‹ ›` toolbar pair. Reads `AppGlobals.recentsManager` directly (no environment dependency). Wires `⌘[` / `⌘]`. Defined in `Pommora/Pommora/NavDropdown/BackForwardButtons.swift`.

---

#### Out of scope (deferrable)

- **`⌘1` … `⌘9` jump to Pinned N** — 10-line accelerator on top of the pinned array.
- **Search-within-dropdown** — useful once Recents fills past ~30 entries; defer until usage shows need.
- **Cross-window Recents sync** — single-window assumption holds. If multiple Pommora windows are ever spawned, each has its own NavDropdown but shares the same `RecentsManager` (which is a `@MainActor` singleton-via-AppGlobals).
