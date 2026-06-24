### Navigation

Pommora's primary navigation-history surface — a **Liquid Glass glyph button** at the toolbar's trailing edge opening a **popover panel** with two toggleable lists: **Pinned** (user-curated, right-click) and **Recents** (auto-tracked).

---

#### Deferred

Drag-to-reorder Pinned (`.onMove` wired but doesn't fire inside the popover — a SwiftUI List + popover view-host interaction); type-chip removal; Pinned/Recents segment polish.

---

#### Toolbar layout

```
LEFT                                                       RIGHT
[ ◯◯◯ ] [≡] [‹] [›] ····· [ ⚙︎ │ ▦ │ ▢ ]
 traffic  sidebar back/fwd     view-settings · navigation · inspector
 lights   toggle  through      ──────── trailing toolbar capsule ────────
```

Left to right:

- **Traffic lights** — OS window controls.
- **Sidebar toggle (`≡`)** — system-provided by `NavigationSplitView`.
- **Back / Forward (`‹ ›`)** — walks the Recents cursor (older / newer). `⌘[` / `⌘]` partners. Stepping does NOT modify Recents order.
- (centre, empty) — no tab strip.
- **Trailing toolbar capsule** — a glyph trio sharing one Liquid Glass capsule: view-settings · navigation · inspector, dividers between. The navigation trigger is the middle segment.

The window title is suppressed (no toolbar title).

---

#### Trigger button

A glyph button — one segment of the trailing toolbar capsule (view-settings · navigation · inspector). `⌘T` opens the panel; a single click does the same, presenting a `.popover` attached to the button.

---

#### Panel structure

```
┌─────────────────────────────────────────┐
│   [ Pinned │ Recents ]                  │  ← segmented picker
├─────────────────────────────────────────┤
│  ▦  Stoic Reflections          Page    │
│  📖 Reading List               Collection│
│  🎨 Studio                     Area     │
│  ▦  Q3 Plan                    Page    │
│  📚 Productivity               Topic    │
│  …                                      │
└─────────────────────────────────────────┘
```

A fixed envelope around a scrollable list — scrolling doesn't expand it. A **segmented picker** at top toggles "Pinned" and "Recents" (Pinned is the default). Rows carry hairline separators.

##### Snapshot pattern (load-bearing)

Pinned and Recents lists render from `@State` snapshot arrays refreshed when the popover opens and after pin/unpin mutations. Direct `@Environment` access through the popover's view host doesn't propagate `@Observable` mutations reliably; the snapshot indirection bypasses that. **Don't unilaterally remove it.**

---

#### Row anatomy

```
[icon] [title — truncates with ellipsis] [type chip]
```

- **Icon** — the entity's own custom `icon` if set (resolved live), else a per-kind default. Defaults are outline (non-`.fill`) so an unset entity never reads as a filled state.
- **Title** — single line, tail-truncated.
- **Type chip** — full-word, caption-sized, secondary foreground, trailing.

**Hover accent:** a subtle background tint in a rounded rect; no revealed chrome.

**Single-click** — highlights via List's native selection chrome. No action.

**Double-click** — closes the popover and routes to the open path (see "Open flow"). Implemented as a simultaneous double-tap gesture, working around NSTableView intercepting List rows' native double-tap.

**Right-click** — context menu with a Pin / Unpin {chip} toggle that flips the entity's pinned state and refreshes the snapshots.

---

#### Open flow

On double-click, the handler dispatches by the row's kind:

- **Page / Collection / Set / Area / Topic / Project** — closes the popover and calls the open closure with a `SidebarSelection`. ContentView's closure writes its selection `@State`; the main detail pane swaps.
- **Agenda / none** — no-op (deferred).

The open action passes a snapshot through the popover host; load-bearing, don't remove.

The dropdown **bypasses the back/forward router** — writing through that `@Observable` from the popover host doesn't fire ContentView's `.onChange` reliably (same root cause as the snapshot pattern). The router stays for back/forward, driven from the main toolbar view host where the change fires reliably.

If selection-building returns nil for a page or set (the host Collection's content lazy-loads per-Set on detail-view appear), the handler falls back to an async walk of the Collections, loading each Collection + Set and retrying at each step.

The dropdown always opens Pages in the main detail pane — it does not consult the Collection's `open_in` mode. PagePreview windows are routed from sidebar page-taps only ([[Pages]] § "Opening behavior").

---

#### Recents rules

- **Storage cap 500** (single source of truth in `RecentsManager`); the dropdown displays the top 100. LRU eviction — the oldest drops when the cap is hit. Re-inserting an existing entity moves it to position 0 rather than duplicating.

**Triggers to bump to position 0:**

1. **Sidebar click** → main detail pane → ContentView records on selection change (unless history-navigation is in progress).
2. **Dropdown double-click** → main detail pane via the same selection write → same record path.

History-navigation is flagged during back/forward stepping so cursor movement doesn't re-record the older entity (which would reset the cursor to 0 and break LRU order).

**What records:** Pages plus the storage containers (Collection / Set). Contexts (Areas / Topics / Projects) stay out — they're reached via the sidebar. Containers are recorded and steppable (Back/Forward walks them) but **hidden from the dropdown's Recents list**, so the dropdown shows Pages only.

---

#### Pinned rules

- **Uncapped, insertion-ordered.** Drag-reorder is wired but doesn't fire end-to-end inside the popover (see Deferred).
- **Single entry point**: right-click any row (Pinned or Recents tab) → "Pin {kind}". Also mirrored on Page rows in the Collection / Set detail views.
- **Separate Codable array** — NOT a flag on Recents entries. Falling off the Recents cap does not un-pin.
- **Open flow identical to Recents** — single = highlight, double = route to main detail pane.
- **Removal**: right-click in the Pinned tab → "Unpin {kind}" → removed from Pinned (stays in Recents if within cap).

---

#### Entity roster + chip text

| Entity kind | Chip text | Recorded into Recents? | Shown in Recents list? | Openable from dropdown? |
|---|---|---|---|---|
| Page | "Page" | ✓ (main-frame land) | ✓ | ✓ |
| Collection | "Collection" | ✓ (steppable) | ✗ (container — hidden) | ✓ (from Pinned) |
| Set | "Set" | ✓ (steppable) | ✗ (container — hidden) | ✓ (from Pinned) |
| Area / Topic / Project | "Area" / "Topic" / "Project" | ✗ — reached via sidebar | — | ✓ (legacy pins still resolve) |
| Agenda | **"Task"** | ✗ (deferred) | — | ✗ (deferred) |
| Homepage | — | excluded | — | never |

"Task" is a chip-label override for Agenda entries (underlying files stay `.task.json` / `.event.json`; only the chip reads "Task").

---

#### Back / Forward arrows

- Position: trailing-left, inside a Liquid Glass pill.
- `‹` (back) — cursor one step DEEPER into Recents (older entity becomes active); `›` (forward) — the opposite.
- Keyboard: `⌘[` and `⌘]` (Safari / Finder / Xcode convention).
- Stepping does NOT modify Recents order — the cursor is separate from LRU position; the record path skips recording while a step-history intent is pending.
- Disabled states: `‹` at the deepest end; `›` at position 0.

---

#### Persistence

**File:** `<nexus>/.nexus/state.json` — per-nexus, nexus-portable. Separate from the machine-level `state.json` under Application Support (managed by `AppState`) — two layers, two files.

The Codable container (`NexusState`) holds a `schemaVersion`, a `recents` array, a `pinned` array, a top-level `cursor` (Recents position for back/forward; 0 = newest), and per-section sidebar-reorder arrays (`areaOrder` / `topicOrder` / `collectionOrder`; nil until the user reorders).

**`EntityStateRef` fields** (`kind` / `id` / `title`):

- `kind` — raw String mapped to the `Kind` enum (`page` / `collection` / `set` / `area` / `topic` / `project` / `agenda`). The raw String allows forward-compat — an unknown or retired kind decodes to no typed kind and is skipped; the pre-Phase-3 `vault` (top container) decodes to `collection`.
- `id` — ULID of the underlying entity (rename-safe).
- `title` — denormalized, refreshed on resolve; used for orphan display after deletion.

Equality / hash is by `(kind, id)` — a renamed entity stays the same record. Writes go through the shared atomic-write contract (temp file + atomic rename) used by the other `.nexus/` config managers.

**Backward-compat:** legacy keys decode then disappear on first save (the encoder writes only the new key): `favorites` → `pinned`, and `vault_order` → `collection_order`. Likewise a persisted `kind: "vault"` decodes to the `.collection` tier.

---

#### Saved (sidebar) ≠ Pinned (dropdown)

Distinct classifications, not redundant:

| Concept | Surface | Data | Trigger |
|---|---|---|---|
| **Saved** (sidebar) | `Saved` section in sidebar — fixed-three pins | `SavedConfig` (`.nexus/saved-config.json`) | System-defined (Homepage / Calendar / Recents) |
| **Pinned** (dropdown) | Pinned tab in dropdown panel | `PinnedManager` (`.nexus/state.json`) | User right-clicks rows in dropdown OR Page rows in Collection/Set detail views |
| **Recents** (dropdown) | Recents tab in dropdown panel | `RecentsManager` (`.nexus/state.json`) | Auto — main-frame land |
| **Recents** (sidebar full-frame view, deferred) | Saved-section `Recents` pin → full-frame view | Same data as dropdown Recents | n/a — read-only view of the same store |

The sidebar `Recents` pin and the dropdown Recents share `RecentsManager` but render different surfaces — the dropdown shows the top 100; the sidebar full-frame view (deferred) shows up to the full store with sort + filter.

---

#### Page-row context menu

The page row's context menu in the Collection / Set detail views offers edit-title, edit-icon, pin / unpin, and delete (destructive, no confirmation, mirroring the sidebar).

---

#### Out of scope (deferrable)

- **`⌘1` … `⌘9` jump to Pinned N** — a thin accelerator on top of the pinned array.
- **Search-within-dropdown** — useful once Recents fills past ~30 entries; defer until needed.
- **Cross-window Recents sync** — the single-window assumption holds; if multiple windows are ever spawned, each has its own Navigation but shares one `RecentsManager`.
