### Nav Dropdown

Pommora's primary navigation-history surface — a **Liquid Glass dropdown button** at the toolbar's trailing edge opening a **popover panel** with two toggleable lists: **Pinned** (user-curated, right-click) and **Recents** (auto-tracked).

The functional layer, click model, context-menu Pin, and detail-view context menus all work.

---

#### Future implementation

Explicit follow-ups not yet wired:

1. **Drag-to-reorder Pinned** — `.onMove` is wired but drag doesn't initiate inside the popover's List (a SwiftUI List + popover view-host interaction issue).
2. **Remove type chip** — drop the trailing chip, rely on the leading icon.
3. **Segmented Pinned/Recents UI polish** — opacity / contrast pass on the picker pill.

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
- **Back / Forward (`‹ ›`)** — walks the Recents cursor (older / newer). `⌘[` / `⌘]` partners. Stepping does NOT modify Recents order.
- (centre, empty) — no tab strip
- **NavDropdown trigger (`square.on.square`)** + **Inspector toggle (`▢`)** — single Liquid Glass pill, two segments, divider between.

Window title suppressed (`.windowToolbarStyle(.unified(showsTitle: false))`).

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
- **Segmented picker** at top with "Pinned" and "Recents" tabs (`PanelMode.pinned` is the default)
- **Row separators**: hairline (`.listRowSeparator(.visible)`)

Panel is a fixed envelope around a scrollable list — scrolling doesn't expand it.

##### Snapshot pattern (load-bearing)

Pinned and Recents lists render from `@State pinnedSnapshot` / `recentsSnapshot` arrays refreshed on `.onChange(of: isPresented)` + after pin/unpin mutations. Direct `@Environment(PinnedManager.self)` access through the popover's view host doesn't propagate `@Observable` mutations reliably; the snapshot indirection bypasses that. **Don't unilaterally remove it.**

---

#### Row anatomy

```
[icon] [title — truncates with ellipsis] [type chip]
```

- **Icon** (`EntityRow.iconName`) — the entity's own custom `icon` if set (resolved live via `SidebarSelection(stateRef:lookup:).resolvedIcon`, since `EntityStateRef` stores no icon), else the per-kind default (`EntityRow.defaultIcon`): Page = `doc.text`, Vault = `book`, Collection = `tray.2`, Space = `rectangle.3.group`, Topic / Project = `folder`, Agenda = `calendar`, unknown kind = `questionmark.circle`. Defaults are outline (non-`.fill`) so an unset entity never reads as a filled state.
- **Title** — `Text(ref.title).lineLimit(1).truncationMode(.tail)`
- **Type chip** — full-word, `.font(.caption)`, `.foregroundStyle(.secondary)`, trailing

**Hover accent:** background tints to `Color.primary.opacity(0.06)` in a 6pt rounded rect. No revealed chrome.

**Single-click** — highlights via List's native selection chrome. No action.

**Double-click** — `.simultaneousGesture(TapGesture(count: 2))` (workaround: SwiftUI List rows have `.onTapGesture(count: 2)` intercepted by NSTableView's selection handler). Closes popover, routes to open path (see "Open flow").

**Right-click** — `.contextMenu` with `Button(isPinned ? "Unpin {chip}" : "Pin {chip}")`. Toggles `AppGlobals.pinnedManager?.toggle(ref)` + refreshes snapshots.

---

#### Open flow

On double-click, `handleOpen(ref)` dispatches by `ref.typedKind`:

- **`.page` / `.vault` / `.space` / `.topic` / `.project` / `.collection`** — closes popover, calls `onOpen(sel)` with a `SidebarSelection` built via `SidebarSelection.init?(stateRef:lookup:)`. ContentView's closure writes to its `sidebarSelection` `@State`; the main detail pane swaps.
- **`.agenda` / `.none`** — no-op. Agenda surfaces ship v0.5.0.

##### Routing architecture

NavDropdownButton takes `onOpen: (SidebarSelection) -> Void` at construction. ContentView passes `{ sel in sidebarSelection = sel }`. The closure captures ContentView's `@State` write path — writes propagate via SwiftUI's normal binding, reliable across view-host boundaries.

The dropdown **bypasses `MainWindowRouter`**: writing through that `@Observable` from the popover view host doesn't fire ContentView's `.onChange` reliably (same root cause as the snapshot pattern). `MainWindowRouter` stays for back/forward, driven by `BackForwardButtons` from the main toolbar view host where `.onChange(of: bringToFrontTick)` fires reliably.

##### Lazy-load fallback

If `SidebarSelection.init?(stateRef:lookup:)` returns nil for a page or collection (the host vault's content lazy-loads per-collection on detail-view appear), `handleOpen` falls back to an async walk of `AppGlobals.pageTypeManager.types` calling `loadAll(for:)` on each vault + collection, retrying at each step. SQLite v0.4.0 makes this O(1) and removes the walk.

##### No preview routing

The dropdown always opens Pages in the main detail pane — it does not consult the vault's `open_in` mode. PagePreview cards are routed from sidebar page-taps only ([[Pages]] § "Opening behavior").

---

#### Recents rules

| Spec | Value |
|---|---|
| Storage cap | **500** (single source of truth in `RecentsManager`) |
| Dropdown display cap | **100** (top 100 from store) |
| Sidebar full-frame view cap (v0.6.0+) | **500** (full store) |
| Eviction | LRU — oldest drops when cap hit |
| Dedupe | Re-inserting an existing entity moves it to position 0, doesn't duplicate |

**Triggers to bump to position 0:**

1. **Sidebar click** → main detail pane → `ContentView.onChange(of: sidebarSelection)` records (unless `RecentsManager.isNavigatingHistory == true`)
2. **Dropdown double-click** → main detail pane via `sidebarSelection = sel` → same `onChange(of: sidebarSelection)` records

`isNavigatingHistory` is true during back/forward stepping so cursor movement doesn't re-record the older entity (which would reset cursor to 0 and break LRU order).

**What records (`RecentsManager.recordableKinds`):** Pages plus the storage containers (Vault / Collection). Contexts (Spaces / Topics / Projects) stay out — they're reached via the sidebar. Containers are recorded and steppable (Back/Forward walks them) but **hidden from the dropdown's Recents list** (`dropdownTop` filters `containerKinds`), so the dropdown shows Pages only.

---

#### Pinned rules

- **Uncapped, insertion-ordered** — drag-reorder is wired (`.onMove(perform:)` → `PinnedManager.move(fromOffsets:toOffset:)`) but doesn't fire end-to-end inside the popover; see Future implementation #2.
- **Single entry point**: right-click any row (Pinned or Recents tab) → "Pin {kind}". Also mirrored in `PageTypeDetailView` / `PageCollectionDetailView` context menus on Page rows.
- **Separate Codable array** — NOT a flag on Recents entries. Falling off the Recents cap does not un-pin.
- **Open flow identical to Recents** — single = highlight, double = route to main detail pane.
- **Removal**: right-click in Pinned tab → "Unpin {kind}" → removed from Pinned (stays in Recents if within cap).

---

#### Entity roster + chip text

| Entity kind | Chip text | Recorded into Recents? | Shown in Recents list? | Openable from dropdown? |
|---|---|---|---|---|
| Page | "Page" | ✓ (main-frame land) | ✓ | ✓ |
| Vault | "Vault" | ✓ (steppable) | ✗ (container — hidden) | ✓ (from Pinned) |
| Collection | "Collection" | ✓ (steppable) | ✗ (container — hidden) | ✓ (from Pinned) |
| Space / Topic / Project | "Space" / "Topic" / "Project" | ✗ — reached via sidebar | — | ✓ (legacy pins still resolve) |
| Agenda | **"Task"** | ✗ (TBD at v0.5.0) | — | ✗ — v0.5.0+ |
| Homepage | — | excluded | — | never |

"Task" is a chip-label override for Agenda entries (underlying files stay `.task.json` / `.event.json`; only the chip reads "Task").

---

#### Back / Forward arrows

- Position: trailing-left (`ToolbarItemGroup(placement: .navigation)`), inside a `.glassEffect()` pill
- `‹` (back) — cursor one step DEEPER into Recents (older entity becomes active)
- `›` (forward) — opposite (newer entity)
- Keyboard: `⌘[` and `⌘]` (Safari / Finder / Xcode convention)
- Stepping does NOT modify Recents order — cursor is separate from LRU position. `MainWindowRouter.requestStep(to:)` sets `pendingIntent = .stepHistory`; ContentView's `onChange(of: bringToFrontTick)` skips record() when intent is `.stepHistory`.
- Disabled states: `‹` at deepest end; `›` at position 0

---

#### Persistence

**File:** `<nexus>/.nexus/state.json` — per-nexus, vault-portable. Separate from the machine-level `~/Library/Application Support/Pommora/state.json` (managed by `AppState`) — two layers, two files.

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

**`EntityStateRef` fields** (`kind` / `id` / `title`):

- `kind` — raw String mapped to the `Kind` enum (`page` / `vault` / `collection` / `space` / `topic` / `project` / `agenda`). Raw String allows forward-compat — an unknown or retired kind decodes with `typedKind == nil` and is skipped.
- `id` — ULID of the underlying entity (rename-safe)
- `title` — denormalized, refreshed on resolve. Used for orphan display after deletion.

`NexusState` also holds a top-level `cursor` (Recents position for back/forward; 0 = newest) and per-section order arrays (`spaceOrder` / `topicOrder` / `vaultOrder`, the persisted sidebar reorder; nil until the user reorders).

**Equality / hash** by `(kind, id)` — a renamed entity stays the same record.

**Atomic-write contract** — `AtomicJSON.write` (temp file + atomic rename), shared with the other `.nexus/` config managers.

##### Backward-compat: `favorites` → `pinned` key

The legacy `favorites` key decodes into `pinned`: `NexusState.CodingKeys` defines both `case pinned` and `case favoritesLegacy = "favorites"`; the decoder reads `pinned` first then falls back, the encoder writes only `pinned` (so the legacy key disappears on first save). Covered by `NexusStateTests.decodesLegacyFavoritesKey()` + `encoderWritesOnlyPinnedKey()`.

---

#### Saved (sidebar) ≠ Pinned (dropdown)

Distinct classifications, not redundant:

| Concept | Surface | Data | Trigger |
|---|---|---|---|
| **Saved** (sidebar) | `Saved` section in sidebar — fixed-three pins | `SavedConfig` (existing, `.nexus/saved-config.json`) | System-defined (Homepage / Calendar / Recents) |
| **Pinned** (dropdown) | Pinned tab in dropdown panel | `PinnedManager` (`.nexus/state.json`) | User right-clicks rows in dropdown OR right-clicks Page rows in Vault/Collection detail views |
| **Recents** (dropdown) | Recents tab in dropdown panel | `RecentsManager` (`.nexus/state.json`) | Auto — main-frame land |
| **Recents** (sidebar full-frame view) | Saved-section `Recents` pin → full-frame view at v0.6.0 | Same data as dropdown Recents | n/a — read-only view of the same store |

Sidebar `Recents` pin and dropdown Recents share `RecentsManager` but render different surfaces — dropdown shows top 100; sidebar full-frame view (v0.6.0) shows up to 500 with sort + filter.

---

#### Detail-view context menus

Right-click on a Page row inside `PageTypeDetailView` or `PageCollectionDetailView` opens a `.contextMenu` with three entries:

- **Rename** — `.alert` with TextField. Commits via the collection-hosted vs root-hosted `renamePage` overloads (`…in:vault:` / `…inVaultRoot:`).
- **Pin / Unpin {kind}** — toggles `AppGlobals.pinnedManager?.toggle(ref)`; label reflects current state + row kind.
- **Delete** — destructive role, no confirmation (mirrors the sidebar). Routes to the `deletePage` overload by parent.

PageTypeDetailView resolves a row's parent via a `parent(for: DetailRow) -> PageParent?` helper (scans vault-root pages, then collections; SQLite v0.4.0 → O(1)). PageCollectionDetailView's parent is always its collection — no lookup. Collection rows in PageTypeDetailView intentionally have NO context menu — sidebar's `PageCollectionRow` is canonical for collection rename/delete.

---

#### Type architecture

- **`EntityStateRef`** (`Pommora/Pommora/NavDropdown/EntityStateRef.swift`) — flat Codable wire-record for state.json. `Hashable, Sendable, Codable`. Equality by `(kind, id)`.
- **`NexusState`** (`Pommora/Pommora/NavDropdown/NexusState.swift`) — top-level Codable container for state.json. Holds `recents`, `pinned`, `cursor`, `schemaVersion`. Custom Codable for backward-compat key fallback.
- **`RecentsManager`** (`Pommora/Pommora/NavDropdown/RecentsManager.swift`) — `@MainActor @Observable`. Holds `entries`, `cursor`, `isNavigatingHistory`. Provides `record(_:)`, `stepBack()`, `stepForward()`, `canStepBack`, `canStepForward`, `dropdownTop`, `load()`, `save()`.
- **`PinnedManager`** (`Pommora/Pommora/NavDropdown/PinnedManager.swift`) — `@MainActor @Observable`. Holds `entries`. Provides `contains(_:)`, `toggle(_:)`, `move(fromOffsets:toOffset:)`, `load()`, `save()`.
- **`MainWindowRouter`** (`Pommora/Pommora/NavDropdown/MainWindowRouter.swift`) — `@MainActor @Observable` bridge for back/forward. `Intent` enum (`.directNavigation` / `.stepHistory`). `requestOpen(to:)` / `requestStep(to:)`. Dropdown bypasses (direct closure from ContentView); only BackForwardButtons + ContentView's `onChange(of: bringToFrontTick)` use it.
- **`SidebarSelection.init?(stateRef:lookup:)`** (`Pommora/Pommora/Sidebar/SidebarSelection.swift`) — bridges `EntityStateRef` → `SidebarSelection`, resolving each kind against a `SidebarLookupBundle` of live managers. Returns nil for non-main-pane kinds (`.agenda`, `.none`) and deleted entities.
- **`EntityRow`** (`Pommora/Pommora/NavDropdown/EntityRow.swift`) — single row view in both lists. Takes `ref: EntityStateRef`, `lookup: SidebarLookupBundle` (resolves the entity's live custom icon), `isPinned: Bool`, `pinAction: () -> Void`. Renders icon + title + chip + hover-tint background + `.contextMenu` with "Pin {chip}" / "Unpin {chip}".
- **`NavDropdownButton`** (`Pommora/Pommora/NavDropdown/NavDropdownButton.swift`) — toolbar trigger + popover panel. Takes `asSegment: Bool` (default `false`) and `onOpen: (SidebarSelection) -> Void`. Owns snapshot state.
- **`BackForwardButtons`** (`Pommora/Pommora/NavDropdown/BackForwardButtons.swift`) — `‹ ›` toolbar pair. Reads `AppGlobals.recentsManager` directly. Wires `⌘[` / `⌘]`.

---

#### Out of scope (deferrable)

- **`⌘1` … `⌘9` jump to Pinned N** — 10-line accelerator on top of the pinned array.
- **Search-within-dropdown** — useful once Recents fills past ~30 entries; defer until needed.
- **Cross-window Recents sync** — single-window assumption holds. If multiple Pommora windows are ever spawned, each has its own NavDropdown but shares `RecentsManager` (`@MainActor` singleton-via-AppGlobals).
