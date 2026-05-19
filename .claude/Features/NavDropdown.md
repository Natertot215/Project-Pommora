### Nav Dropdown

Pommora's primary navigation-history surface — a **Liquid Glass dropdown button** in the trailing edge of the toolbar that opens a **popover panel** containing two toggleable lists: **Favorites** (user-curated) and **Recents** (auto-tracked). Replaces the horizontal tab strip from the v0.0–v0.2.6 era and consolidates navigation chrome into a single always-visible control.

Locked at v0.2.8 brainstorm (2026-05-18). Pivots away from `Navigation-Bar.md`'s tab-strip model. The two-toolbar-row problem and `.unified` chrome conflict that pushed the pivot are resolved by collapsing tabs + the `+` button into one dropdown.

---

#### Toolbar layout

```
LEFT                                                       RIGHT
[ ◯◯◯ ] [≡] [‹] [›] ····· [▦ NavDropdown] [▢ Inspector]
 traffic  sidebar back/fwd     square.on.square    sidebar.trailing
 lights   toggle  through      Liquid Glass        inspector toggle
                  Recents      (.glass style)
```

Left to right:

- **Traffic lights** — OS window controls
- **Sidebar toggle (`≡`)** — system-provided by `NavigationSplitView`
- **Back / Forward (`‹ ›`)** — walks the Recents list (older / newer). `⌘[` / `⌘]` are the keyboard partners. Becomes a real navigation control rather than the v0.0-era no-op.
- (centre, empty) — no tab strip
- **NavDropdown trigger (`square.on.square`)** — Liquid Glass button; opens the popover panel
- **Inspector toggle (`▢`)** — `sidebar.trailing`, anchored to the inspector's segment of the unified toolbar

Window title is suppressed (`.windowToolbarStyle(.unified(showsTitle: false))`).

---

#### Trigger button

| Spec | Value |
|---|---|
| SF Symbol | `square.on.square` |
| Style | `.buttonStyle(.glass)` (macOS 26+; no fallback needed — Pommora is macOS 26-only) |
| Placement | `ToolbarItem(placement: .primaryAction)`, trailing-right, immediately before the inspector toggle |
| Keyboard | `⌘T` opens the panel (repurposed from the old "new tab" shortcut) |
| Activation | Single click or `⌘T`; opens `.popover(isPresented:arrowEdge:)` attached to the button |

The button itself uses Liquid Glass via `.buttonStyle(.glass)`. The popover panel does NOT use `.glassEffect()` — popovers already render system vibrancy; stacking would double up.

---

#### Panel structure

```
┌─────────────────────────────────────────┐
│   [ Favorites │ Recents ]               │  ← segmented Picker
├─────────────────────────────────────────┤
│  ▦  Stoic Reflections          Page  ★ │
│  📖 Reading List               Vault    │
│  🎨 Studio                     Space    │
│  ▦  Q3 Plan                    Page  ★ │
│  ▦  Meeting Notes              Page     │
│  📚 Productivity               Topic    │
│  …                                      │
└─────────────────────────────────────────┘
```

- Width: ~320pt (fixed via `.frame(width: 320)`)
- Max height: ~420pt (list scrolls within)
- Top: `Picker(...)` `.pickerStyle(.segmented)` bound to a `PanelMode` enum — **Favorites left (primary), Recents right**
- Body: `List(selection:)` with default macOS row separators (`.listStyle(.inset)`)
- Background: system popover vibrancy — no custom material

Scrolling the list does NOT expand the panel; the panel is a fixed envelope around a scrollable list.

---

#### Row anatomy

```
[icon] [title — truncates with ellipsis] [type chip] [★ on hover]
```

- **Icon** — entity's symbol (Page = `doc.text`, Vault = `book`, etc.), 18pt frame
- **Title** — `Text(title).lineLimit(1)`
- **Type chip** — full-word, `.font(.caption)`, `.foregroundStyle(.secondary)`, trailing
- **Hover star** — `.onHover`-revealed; filled (`star.fill`) if favorited, outline (`star`) if hovering and not favorited. Click toggles favorite state. The filled star stays visible even without hover for favorited rows.

Row click on Recents tab → opens preview window (see "Click flow" below). Row click on Favorites tab → same opening flow.

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

1. **Sidebar click** → entity lands in main detail pane → record
2. **Dropdown click (full-frame-eligible)** → standalone window opens → user clicks Expand → entity loads into main detail pane → record (the standalone window dismisses)
3. **Item click anywhere** → `ItemWindow` popover opens → record

**Crucial: standalone window dismissed WITHOUT pressing Expand is NOT recorded.** This is the "preview gate" — peek without commitment.

---

#### Favorites rules

- **Uncapped, user-ordered** (insertion order; reorder out of v0.2.8 scope)
- **Single entry point**: hover-star on a Recents-tab row. No sidebar context-menu integration, no editor toolbar button. Self-contained inside the dropdown.
- **Separate Codable array** — NOT a flag on Recents entries. An entry falling off the Recents cap does not un-favorite itself.
- **Click flow identical to Recents** — opens via standalone-window preview gate (or `ItemWindow` popover for Items)
- **Removal**: hover the row in the Favorites tab → click the filled star → entity removed from Favorites (stays in Recents if still within cap)

---

#### Entity roster + chip text

| Entity kind | Chip text | Recents trigger | In v0.2.8? |
|---|---|---|---|
| Page | "Page" | main-frame land | ✓ |
| Vault | "Vault" | main-frame land | ✓ |
| Collection | — | excluded for v0.2.8 simplicity | ✗ — revisit later |
| Space | "Space" | main-frame land | ✓ |
| Topic | "Topic" | main-frame land | ✓ |
| Sub-topic | "Sub-topic" | main-frame land | ✓ |
| Item | "Item" | popover open (`ItemWindow`) | ✓ |
| Agenda | **"Task"** | (TBD at v0.6.0) | ✗ — v0.6.0+ |
| Homepage | — | excluded | never |

Collection exclusion is a v0.2.8 scope trim, not a permanent rule — the data layer treats it as gated, easy to enable later. "Task" is a chip-label override for Agenda items (underlying entity stays `.agenda.json`; the chip just reads "Task").

---

#### Click → standalone window flow (full-frame-eligible entities)

1. User clicks a row in the dropdown panel
2. Popover dismisses; a new macOS window spawns via `WindowGroup(for: EntityRef.self)` within the same Pommora process — **not a separate app instance**
3. The window is draggable, resizable, repositionable freely. Minimal toolbar per `Pages.md:110` ("Standalone windows have their own minimal toolbar — no sidebar, no tab strip")
4. The window's toolbar carries an **Expand button** (SF Symbol `arrow.up.left.and.arrow.down.right` or similar — final choice at implementation)
5. **Expand action:** focuses the main Pommora window, sets `SidebarSelection` to this entity, the main detail pane swaps to render it, and the standalone window dismisses. The Recents list bumps this entity to position 0.
6. **Dismiss action** (close button, `⌘W`): standalone window closes. Recents is **not** modified — the user peeked but did not commit.

---

#### Click → popover flow (Items)

Items can't open in main full-frame — they use the existing `ItemWindow` popover. Clicking an Item row in the dropdown opens the `ItemWindow` directly (no standalone-window gate) and immediately bumps Recents. The popover IS the opening surface for Items, so there's no separate commit step.

When Agenda ships at v0.6.0, the same flow applies — Agenda items have a popover-only surface; chip reads "Task"; opening from the dropdown bumps Recents immediately.

---

#### Back / Forward arrows

- Position: trailing-left in the toolbar, between the sidebar toggle and the empty centre
- `‹` (back) — moves the active cursor one step DEEPER into the Recents list (older entity becomes active in the main detail pane)
- `›` (forward) — opposite direction (newer entity)
- Keyboard partners: `⌘[` and `⌘]` (Safari / Finder / Xcode convention)
- Stepping through Recents does NOT modify the Recents order — the cursor is a separate concept from the LRU position
- Disabled states: `‹` disabled when at the deepest end; `›` disabled when at position 0

---

#### Persistence

**File:** `<nexus>/.nexus/state.json` — per-nexus, vault-portable. **Does not exist on disk yet**; first creation lands with v0.2.8. The existing machine-level `~/Library/Application Support/Pommora/state.json` (managed by `AppState`) is unaffected — these are two separate files for two different layers (machine-global vs per-nexus).

**Codable shape:**

```json
{
  "schemaVersion": 1,
  "recents": [
    { "kind": "page", "id": "01HF...", "title": "Stoic Reflections" },
    { "kind": "vault", "id": "01HG...", "title": "Reading List" }
  ],
  "favorites": [
    { "kind": "page", "id": "01HF...", "title": "Stoic Reflections" }
  ],
  "cursor": 0
}
```

**`RecentRef` / `FavoriteRef` fields:**

- `kind` — enum: `page` / `vault` / `space` / `topic` / `subtopic` / `item` / `agenda` (Collection reserved but unused in v0.2.8)
- `id` — ULID of the underlying entity (rename-safe)
- `title` — denormalized, refreshed on resolve. Used for orphan display when the entity has been deleted on disk
- `cursor` (top-level) — current position in Recents for back/forward arrows; 0 = newest active

**Atomic-write contract** — same pattern as existing managers (`SavedConfigManager`, `AppState`). Write to a temp file, fsync, rename.

---

#### EntityRef + WindowGroup

The v0.2.7-shipped `PageRef` type (`{ pageID, vaultID, collectionID? }`) is generalized into `EntityRef`:

```swift
enum EntityRef: Hashable, Codable {
    case page(pageID: String, vaultID: String, collectionID: String?)
    case vault(vaultID: String)
    case collection(vaultID: String, collectionID: String)  // reserved, not wired in v0.2.8
    case space(spaceID: String)
    case topic(topicID: String)
    case subtopic(subtopicID: String, parentTopicID: String)
    // item / agenda excluded — they use ItemWindow, not WindowGroup
}
```

A single `WindowGroup(for: EntityRef.self)` scene in `PommoraApp` dispatches on the case to render the matching existing view (`PageEditorView`, `VaultDetailView`, `ContextDetailPlaceholder`). No new per-entity views are needed — the standalone window reuses what the main detail pane already has.

Items and Agenda items do not appear in `EntityRef` — they use the popover `ItemWindow` surface and have no standalone-window representation.

---

#### Saved (sidebar) ≠ Favorites (dropdown)

These are **distinct classifications**, not redundant:

| Concept | Surface | Data | Trigger |
|---|---|---|---|
| **Saved** (sidebar) | `Saved` section in sidebar — fixed-three pins | `SavedConfig` (existing, `.nexus/saved-config.json`) | System-defined (Homepage / Calendar / Recents) |
| **Favorites** (dropdown) | Favorites tab in dropdown panel | `FavoritesManager` (new, in `.nexus/state.json`) | User hover-stars rows in dropdown |
| **Recents** (dropdown) | Recents tab in dropdown panel | `RecentsManager` (new, in `.nexus/state.json`) | Auto — main-frame land or popover open |
| **Recents** (sidebar full-frame view) | Saved-section `Recents` pin → full-frame view at v0.6.0 | Same data as dropdown Recents | n/a — read-only view of the same store |

The sidebar `Recents` pin and the dropdown Recents share the same underlying `RecentsManager` store but render different surfaces — dropdown shows top 100 quickly; sidebar full-frame view at v0.6.0 shows up to 500 with sort + filter.

---

#### v0.2.8 implementation order

Each step ships green standalone (stub-and-progressively-replace per paradigm decision #4):

1. **Data layer** — `RecentsManager` + `FavoritesManager` + `state.json` Codable types + atomic-write + LRU + unit tests. Zero UI dependency.
2. **`EntityRef` + standalone window scene** — generalize `PageRef` to `EntityRef`, add `WindowGroup(for: EntityRef.self)`, build Expand button. Unwired from triggers at this point.
3. **Recents trigger wiring** — hook three points: sidebar selection (existing routing), main-detail-pane landing from Expand, `ItemWindow` open. Each call site adds one `RecentsManager.record(...)` invocation.
4. **Dropdown panel UI** — toolbar trigger button + popover + segmented Picker + List + row chrome + hover star. No favoriting logic yet.
5. **Favorites wiring** — hook the hover-star tap to `FavoritesManager.toggle(...)`, render Favorites segment.
6. **Back / Forward arrows** — toolbar buttons + `⌘[` / `⌘]` shortcuts + cursor logic.

---

#### Out of scope for v0.2.8 (deferrable)

- **Collection** in Recents/Favorites — easy add when needed; data layer pre-supports.
- **`⌘1` … `⌘9` jump to Favorite N** — 10-line accelerator on top of the favorites array.
- **Drag-to-reorder favorites** — favorites stay insertion-ordered.
- **Search-within-dropdown** — useful once Recents fills past ~30 entries; defer until usage shows need.
- **Tear-off / detach standalone windows into tab groups** — macOS native `⌥⌘T` Merge All Windows already works; no Pommora-side wiring needed.
- **Cross-window Recents sync** — single-window assumption holds for the main Pommora window. Standalone windows spawned via `WindowGroup` don't have their own Recents list; the main window's `RecentsManager` is the single source.

---

#### Open until v0.2.8 ships

- **Expand button SF Symbol** — `arrow.up.left.and.arrow.down.right` vs `rectangle.center.inset.filled` vs `arrow.up.forward.square` — final pick at implementation when the button renders alongside the standalone window's minimal toolbar
- **Active-row visual on segmented Picker** — `.segmented` default works; possible custom Liquid-Glass-styled segments if the default reads bland against the popover material
- **Hover-star tooltip text** — "Add to Favorites" / "Remove from Favorites" or shorter
- **Standalone window default size + position** — likely centered, ~600pt × 700pt; revisit when first window spawns in testing
