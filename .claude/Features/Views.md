## Views

The detail-pane surfacing layer for Pages. Every storage container (Page Type / Page Collection) carries one or more **saved views** in its sidecar; a toolbar Views dropdown switches between them. Two renderers ship — a custom **Table** and a **Gallery** — both fed by one pure in-memory pipeline. Native `Table`, `DetailRow`, and `PropertyColumnBuilder` are retired (registry decision #20).

Conceptual ledger + platform/SDK research → `// Planning//Superseded//06-11-Views-Spec.md`; per-task implementation record → `// Planning//Superseded//06-11-Views-Plan.md`. This doc is the spec-as-fact: how the system works now.

---

#### SavedView v2 (sidecar schema)

Each container's `views[]` holds `SavedView` objects (snake_case, all new fields `decodeIfPresent`):

```json
{
  "id": "view_<ULID>",
  "name": "All Pages",
  "icon": "tablecells",
  "type": "table | board | list | cards | gallery",
  "property_order": ["_title", "prop_<ulid>", "_tier1", "_modified_at"],
  "hidden_properties": ["prop_<ulid>"],
  "sort": [{ "property_id": "_modified_at", "direction": "descending" }],
  "filter": { "match": "all | any", "rules": [{ "property_id": "...", "op": "...", "value": "..." }] },
  "group": { "kind": "structural" },
  "column_widths": { "_title": 240.0 },
  "collapsed_groups": ["<containerULID | option value | _ungrouped>"],
  "card_size": "small | medium | large",
  "show_cover": false,
  "show_banner": true
}
```

- **`property_order`** is one ordered list of every column id (including `_title`, the tier columns, `_modified_at`) paired with the **`hidden_properties`** set — replacing the old two-array visible/hidden model. Legacy `visible_properties` decodes once (`property_order = ["_title"] + legacy`, decode-only). Unaccounted schema properties append at resolution. `ReservedPropertyID` carries `title = "_title"`; Title is movable to any position, never hideable. The `cover` field is never a column.
- **`group`** (GroupConfig) is a tagged object discriminated on `kind`: `{"kind":"structural"}` | `{"kind":"property","property_id":"...","order":[...]}` | `{"kind":"flat"}` → Swift cases `.structural` / `.property(PropertyGrouping)` / `.flat`. `group == nil` and any unknown `kind` decode to `.structural` (lenient — a throw would poison the whole sidecar).
- **Sort presets** encode as reserved property ids: Title → `_title`, Created → `_id` ascending (ULID = creation order), Recent → `_modified_at` descending. Stored as the existing `[SortCriterion]?` array (UI restricts to one). `PageType.default_sort` folds into the minted default view's `sort`, keeps decoding, is never written again.
- **`card_size`** small/medium/large → 8/6/4 cards per row (`CardSize.columnsPerRow`).
- **`show_cover`** defaults **OFF** (nil/false = hidden). **`show_banner`** defaults **ON when a container banner exists** (the toggle exists to hide it per view).
- **No SQLite changes** — views are sidecar-only.

---

#### View Pipeline

One pure, unit-tested pipeline feeds both renderers: **fetch → filter → group → sort within groups → `[ResolvedGroup]`**. Lives in `Detail//ViewPipeline//` with no SwiftUI imports.

- **Fetch** — `ViewItemSource` reads the `@Observable` manager caches (already manual-order-resolved) and stamps each `ViewItem` with its `PageParent` + Set label. Runs entirely in-memory off `PageMeta.frontmatter`, so any property edit recomputes the view instantly (no extra disk reads, `IndexQuery` not in this path).
- **Filter** — `FilterEvaluator.matches` applies the flat rule list under Match All/Any with conservative per-type operators (full operator matrix in the spec); unknown `op` = rule no-op.
- **Group** — `GroupResolver.resolve` produces `[ResolvedGroup]`. `.structural` (the default): vault scope groups by Collection with Sets nested as children; collection scope groups by Set plus an ungrouped root band (zero Sets → one ungrouped band, no header — the flat look). `.property` flattens to buckets in schema-option order (+ an `order` override) plus an `_ungrouped` bucket. `.flat` is a single group.
- **Sort** — `ViewSortComparator.comparator` sorts within each group; `nil` = manual order. `_title` case-insensitive, `_id` lexicographic, `_modified_at` with a `createdAt` fallback, select/status by schema option order. (Named `ViewSortComparator` to avoid collision with Foundation's `SortComparator`.)

Mutations route through existing manager APIs: reorder → `reorderPages` (collection/set/vault-root), structural move → `movePage`, property rewrite → `updatePageProperty`.

**Prerequisite fix shipped first** — the order-clobber race: `reorderPages` wrote `page_order` to disk but `PageTypeManager`'s in-memory copy went stale, so the next `updateView` whole-struct save clobbered the reorder. `updateView` now reads the sidecar fresh (disk read-modify-write) before persisting any view config.

---

#### Table Renderer

`CustomTableView` — a visual 1-1 of native macOS `Table`, except alternating rows use the subtler **quinary fill** (`PUI.Fill.field`) instead of Apple's lighter grey.

- **Layout** — outer `ScrollView(.horizontal)` holding a `frame(width: totalWidth)` pane; inner `ScrollView(.vertical)` + `LazyVStack`. The column header is fixed via `.safeAreaInset(edge: .top)` (fixed vertically, pans horizontally in column alignment). **Group headers render as native-style disclosure rows** (chevron + grouping-value label + count) that scroll with content — not pinned bands. The container affordances the old Collection/Set rows carried (Open / Edit Title / Edit Icon / Delete with dialogs) migrate onto these group rows.
- **Rows** — 26pt fixed-height cells reusing `PropertyCellEditor` / `PropertyCellDisplay` unchanged (display-first, popover commit-on-dismiss). Hover via one container `onContinuousHover` + row math. **Rename is context-menu only** (no click-to-edit on Title cells); icon click → IconPicker. There is no cover access from the table view at all.
- **Columns** — `TableColumnResolver` maps `property_order` + schema → resolved columns (each carrying its property-type SF Symbol for the header). Resize via a 5pt trailing-handle `DragGesture` (60pt min clamp, `pointerStyle(.columnResize)`), persisted on `.onEnded`. Header drag re-arranges (insertion from prefix-sum math, writes `property_order`). Header right-click → **Hide Column** (`_title` exempt), writes `hidden_properties`.
- **Selection + keyboard** — `Set<RowID>` + anchor; plain/⌘/⇧ click via `onModifierKeysChanged`; `.focusable()` container + `onMoveCommand` arrows + type-select; double-click opens via `PageOpenRouter`.

---

#### Gallery Renderer

`GalleryView` — `LazyVGrid` of cards, one section per `ResolvedGroup` (same disclosure headers + collapse as the table).

- **Card anatomy** — cover area (only when `show_cover` is on; empty fill when no cover is set) → header (icon + title) → property zones: **chips** (select / multiSelect / status / tier relations + the Set label chip at vault scope), **meta** (dates / number / checkbox), **links** (url). Zones order by `property_order`, respect the hidden set, exclude cover always, and are **fully interactive** — the same popover editors as table cells assign and remove values on the card.
- **Interaction** — single click selects; **double-click on the title text renames inline; double-click anywhere else opens** the page; icon click edits the icon; right-click the card = page context menu; right-click the visible cover area = Set / Change / Remove Cover.
- Covers load through the **Nuke** pipeline (`LazyImage` + `ImageProcessors.Resize`, cross-launch disk cache).

---

#### Covers + Banners

- **Cover** — a root `cover` frontmatter field on the page (nexus-relative path), written via `updatePageFrontmatter` (never `updatePageProperty`). It **never appears in any properties UI** — not Edit Properties, not the Layout visibility list, not the inspector. Access points: the Layout pane's Display toggle, right-clicking a card's visible cover area, and (a future MarkdownPM session) inline on the page.
- **Banner** — a `banner` field on the container sidecar (`_pagetype.json` / `_pagecollection.json`), hideable per view via `show_banner`. With no banner set, the **22pt (`.title` bold) detail title** sits as plain chrome above the content. With one set, a **180pt full-width image bleeds edge-to-edge under the sidebar + inspector** via Apple's `backgroundExtensionEffect()` (macOS 26 Liquid Glass; the Landmarks-sample pattern), and the **title overlays it at the bottom-leading corner**. **Add Banner is a hover-revealed button shown only in the no-banner state** (the page add-icon pattern) → file picker; once set, a Change / Remove menu manages it. Written via `PageTypeManager.setBanner`.
- Image files are copied into **`.nexus//assets//<entityID>//`** by `CoverAssetStore` (collision-suffix loop + a 500MB hard-cap guard, reusing `AttachmentManager`'s copy logic).

---

#### Views Dropdown + Multi-View Model

- A window-toolbar Views button sits left of the ViewSettings capsule (popover pattern). It's a **fixed-width icon-only button** showing the active view's icon (default `rectangle.3.group`); the old two-mode "Show View Title" toggle was dropped (`views_button_style` now dormant). **Open issue:** on macOS 26 the primary-action controls (views / settings / nav / inspector) collapse into the `»` overflow. The `NSGlassContainerView` theory was refuted; the leading (UNCONFIRMED) hypothesis is `.primaryAction` resolving against the narrow sidebar column when the `.toolbar` is hosted on the `NavigationSplitView` root — being tested via a host-move to the detail.
- The dropdown is one popover of custom rows (`.chipDropdownPanel()`, 280pt): icon + view name left, a muted right-side type label (**"Table"** / **"Gallery | Small"** — pipe + full size word) that is itself a button toggling an **inline type-switcher** (Table + Gallery active; Board/List/Cards muted, written via `type` in place). Row click = set active + dismiss. Name edits inline (double-click), icon via IconPicker. Context menu: Rename / Duplicate / Delete (≥1-view guard). Footer "New View" mints **"Untitled View"** (type `.table`).
- **Active view persists per container** in `state.json` (`active_views: {containerID: viewID}`), surfaced by an `@Observable ActiveViewStore` on `NexusEnvironment`; missing entry → first view. All detail-view rendering and every View-Settings pane resolve the active view through this store.

---

#### View Settings Panes

The View Settings popover is active-view-scoped. Five panes:

- **Edit Properties** — **schema-only**: add / rename / type-change / delete / reorder properties. Tier columns and Modified are removed from its list (they're non-editable); it carries no visibility toggles.
- **Layout** — per-view display config: **Display Banner** toggle, **Card Size** (gallery), the **Property Visibility** eye-list (per-view show/hide + drag-order over ALL columns — user properties, the tier columns Projects/Topics/Areas, and Modified; `_title` pinned non-hideable; cover never listed), and a muted **Wrap Text** row (table; dynamic row heights are a later pass). The vault-scoped open-in selector renamed to **Open Pages In**.
- **Sort** — single picker: Manual, Title A→Z / Z→A, Created, Recent, or any property asc/desc.
- **Filter** — flat rule list + Match All/Any.
- **Group** — Default (structural) / property picker / Remove Grouping (`.flat`).

The standalone Property Visibility pane is retired.

---

#### Drag Semantics

Drag runs on the macOS 26 system drag-session APIs (deployment floor 26.4): `.draggable` page sources + `dropDestination(for:isEnabled:action:)` receiving a `DropSession`, with `onDropSessionUpdated` driving a live insertion line + group-header highlight during hover. Only page rows are drag sources (group rows are not). `GroupDropPlanner` (pure, tested) resolves intent:

- **Reorder** — manual-only (active when `sort == nil`) and same-container; writes `reorderPages`.
- **Structural-group drop** — a real file move (`movePage`).
- **Property-group drop** — a frontmatter rewrite of that property's value (`updatePageProperty`; the ungrouped bucket writes `nil`).

The same upgraded insertion-line mechanics apply to the settings reorder surfaces (Select/Status option editors). Drop targets are kept out of `List` (unfixed macOS bug). The pure-`DragGesture` coordinator fallback stays isolated behind `RowDragCoordinator` if the system feel is ever rejected.

---

#### Deferred

Board / List / Cards renderers (their `type` cases carry through the data model); multi-level sort chains; nested filter groups; page-editor rendering of the cover banner (MarkdownPM); functional table text-wrapping (dynamic row heights).
